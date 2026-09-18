import CoreGraphics
import CoreImage
import Foundation

/// Wraps the Core Image generator filters for the symbologies Apple ships
/// (QR, Aztec, PDF417 and Code 128).
enum CoreImageBarcodeGenerator {

    static let supported: Set<BarcodeSymbology> = [.qr, .aztec, .pdf417, .code128]

    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    static func makeImage(
        payload: String,
        symbology: BarcodeSymbology,
        targetPixelWidth: Int
    ) throws -> CGImage {
        guard let filter = try makeFilter(payload: payload, symbology: symbology),
              let output = filter.outputImage
        else {
            throw BarcodeError.renderingFailed
        }

        let extent = output.extent
        guard extent.width > 0, extent.height > 0 else { throw BarcodeError.renderingFailed }

        // Integer scaling with nearest-neighbour sampling keeps module edges crisp;
        // any smoothing here costs scan reliability on a phone screen.
        let rawScale = CGFloat(targetPixelWidth) / extent.width
        let scale = max(1, rawScale.rounded(.down))
        let scaled = output.samplingNearest().transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        guard let image = context.createCGImage(scaled, from: scaled.extent) else {
            throw BarcodeError.renderingFailed
        }
        return image
    }

    private static func makeFilter(payload: String, symbology: BarcodeSymbology) throws -> CIFilter? {
        switch symbology {
        case .qr:
            guard let data = payload.data(using: .utf8) else {
                throw BarcodeError.unsupportedEncoding(symbology.displayName)
            }
            let filter = CIFilter(name: "CIQRCodeGenerator")
            filter?.setValue(data, forKey: "inputMessage")
            // "M" recovers from about 15% damage, the sweet spot for a screen held at a scanner.
            filter?.setValue("M", forKey: "inputCorrectionLevel")
            return filter
        case .aztec:
            guard let data = payload.data(using: .utf8) else {
                throw BarcodeError.unsupportedEncoding(symbology.displayName)
            }
            let filter = CIFilter(name: "CIAztecCodeGenerator")
            filter?.setValue(data, forKey: "inputMessage")
            filter?.setValue(23, forKey: "inputCorrectionLevel")
            return filter
        case .pdf417:
            guard let data = payload.data(using: .isoLatin1) ?? payload.data(using: .utf8) else {
                throw BarcodeError.unsupportedEncoding(symbology.displayName)
            }
            let filter = CIFilter(name: "CIPDF417BarcodeGenerator")
            filter?.setValue(data, forKey: "inputMessage")
            // Compaction is left on automatic: boarding pass payloads mix digits and letters.
            return filter
        case .code128:
            guard let data = payload.data(using: .ascii) else {
                throw BarcodeError.unsupportedEncoding(symbology.displayName)
            }
            let filter = CIFilter(name: "CICode128BarcodeGenerator")
            filter?.setValue(data, forKey: "inputMessage")
            filter?.setValue(10, forKey: "inputQuietSpace")
            filter?.setValue(32, forKey: "inputBarcodeHeight")
            return filter
        case .code39, .ean13, .ean8, .upcA, .upcE, .itf14:
            throw BarcodeError.unsupportedEncoding(symbology.displayName)
        }
    }
}
