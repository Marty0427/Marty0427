import CoreGraphics
import Foundation

/// Draws encoded modules into a bitmap. Bars are always an exact whole number of pixels wide
/// so the symbol stays sharp and evenly spaced, which matters more to a laser scanner than size.
enum BitmapBarcodeRenderer {

    /// Quiet zone in modules on each side. EAN requires at least 9; 10 is a safe default.
    static let defaultQuietZoneModules = 10

    static func makeImage(
        from barcode: LinearBarcode,
        moduleWidth: Int,
        height: Int,
        quietZoneModules: Int = defaultQuietZoneModules
    ) throws -> CGImage {
        let moduleWidth = max(1, moduleWidth)
        let height = max(1, height)
        let quietZone = max(0, quietZoneModules)
        let totalModules = barcode.moduleCount + quietZone * 2
        let width = totalModules * moduleWidth

        guard
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            )
        else {
            throw BarcodeError.renderingFailed
        }

        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(gray: 0, alpha: 1)

        // Merge neighbouring bars into one rect: fewer fills, and no seams between them.
        var runStart: Int?
        for index in 0...barcode.moduleCount {
            let isBar = index < barcode.moduleCount && barcode.modules[index]
            switch (isBar, runStart) {
            case (true, nil):
                runStart = index
            case (false, .some(let start)):
                let x = (quietZone + start) * moduleWidth
                let runWidth = (index - start) * moduleWidth
                context.fill(CGRect(x: x, y: 0, width: runWidth, height: height))
                runStart = nil
            default:
                break
            }
        }

        guard let image = context.makeImage() else { throw BarcodeError.renderingFailed }
        return image
    }

    /// Picks a module width that fills `targetPixelWidth` as closely as possible without
    /// going under one pixel per module.
    static func moduleWidth(forTotalModules modules: Int, targetPixelWidth: Int) -> Int {
        guard modules > 0 else { return 1 }
        let usable = modules + defaultQuietZoneModules * 2
        return max(1, targetPixelWidth / usable)
    }
}
