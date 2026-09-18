import CoreGraphics
import Foundation

/// A rendered symbol, boxed so it can live in an `NSCache`.
final class RenderedBarcode {
    let image: CGImage
    /// What is printed under the symbol, e.g. the completed 13 digit EAN.
    let humanReadable: String

    init(image: CGImage, humanReadable: String) {
        self.image = image
        self.humanReadable = humanReadable
    }

    var pixelSize: CGSize { CGSize(width: image.width, height: image.height) }
}

/// Single entry point for turning a payload into a scannable image, whichever engine is needed.
enum BarcodeRenderer {

    /// - Parameter pixelWidth: target width in *pixels*, i.e. points multiplied by the screen scale.
    static func render(
        payload: String,
        symbology: BarcodeSymbology,
        pixelWidth: Int
    ) throws -> RenderedBarcode {
        let normalized = try BarcodeValidator.normalize(payload, for: symbology)
        let width = max(128, pixelWidth)

        if CoreImageBarcodeGenerator.supported.contains(symbology) {
            let image = try CoreImageBarcodeGenerator.makeImage(
                payload: normalized,
                symbology: symbology,
                targetPixelWidth: width
            )
            return RenderedBarcode(image: image, humanReadable: normalized)
        }

        let barcode = try LinearBarcodeEncoder.encode(normalized, symbology: symbology)
        let moduleWidth = BitmapBarcodeRenderer.moduleWidth(
            forTotalModules: barcode.moduleCount,
            targetPixelWidth: width
        )
        let renderedWidth = (barcode.moduleCount + BitmapBarcodeRenderer.defaultQuietZoneModules * 2) * moduleWidth
        let height = max(64, Int((CGFloat(renderedWidth) / symbology.preferredAspectRatio).rounded()))
        let image = try BitmapBarcodeRenderer.makeImage(
            from: barcode,
            moduleWidth: moduleWidth,
            height: height
        )
        return RenderedBarcode(image: image, humanReadable: barcode.humanReadable)
    }
}

/// Memory cache in front of `BarcodeRenderer`. Rendering is cheap but happens on every scroll
/// tick of the wallet grid, so the results are worth keeping.
final class BarcodeImageCache: @unchecked Sendable {
    static let shared = BarcodeImageCache()

    private let cache = NSCache<NSString, RenderedBarcode>()

    init(countLimit: Int = 120) {
        cache.countLimit = countLimit
    }

    func render(payload: String, symbology: BarcodeSymbology, pixelWidth: Int) throws -> RenderedBarcode {
        // Bucket widths so a few pixels of layout drift do not invalidate the entry.
        let bucket = max(1, pixelWidth / 64) * 64
        let key = "\(symbology.rawValue)|\(bucket)|\(payload)" as NSString

        if let cached = cache.object(forKey: key) { return cached }

        let rendered = try BarcodeRenderer.render(payload: payload, symbology: symbology, pixelWidth: bucket)
        cache.setObject(rendered, forKey: key)
        return rendered
    }

    func removeAll() {
        cache.removeAllObjects()
    }
}
