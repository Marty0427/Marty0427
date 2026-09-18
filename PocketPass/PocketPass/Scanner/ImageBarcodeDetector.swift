import CoreGraphics
import ImageIO
import UIKit
import Vision

/// Finds barcodes in a still image, so a screenshot of a boarding pass or a photo of a
/// loyalty card can be imported without pointing the camera at anything.
enum ImageBarcodeDetector {

    enum DetectionError: LocalizedError {
        case noImageData
        case nothingFound

        var errorDescription: String? {
            switch self {
            case .noImageData: return "That image couldn’t be opened."
            case .nothingFound: return "No barcode was found in that image."
            }
        }
    }

    static func symbology(for visionSymbology: VNBarcodeSymbology) -> BarcodeSymbology? {
        switch visionSymbology {
        case .qr: return .qr
        case .aztec: return .aztec
        case .pdf417: return .pdf417
        case .code128: return .code128
        case .code39, .code39Checksum, .code39FullASCII, .code39FullASCIIChecksum: return .code39
        case .ean13: return .ean13
        case .ean8: return .ean8
        case .upce: return .upcE
        case .itf14, .i2of5, .i2of5Checksum: return .itf14
        default: return nil
        }
    }

    /// Every storable code found in the image, largest first — the pass is usually the
    /// biggest code on a screenshot.
    static func detect(in image: UIImage) async throws -> [ScanResult] {
        guard let cgImage = image.cgImage else { throw DetectionError.noImageData }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)

        let observations: [VNBarcodeObservation] = try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNDetectBarcodesRequest()
                if let supported = try? request.supportedSymbologies() {
                    let wanted: Set<VNBarcodeSymbology> = [
                        .qr, .aztec, .pdf417, .code128, .code39, .code39Checksum,
                        .code39FullASCII, .code39FullASCIIChecksum, .ean13, .ean8,
                        .upce, .itf14, .i2of5, .i2of5Checksum,
                    ]
                    request.symbologies = supported.filter(wanted.contains)
                }

                let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
                do {
                    try handler.perform([request])
                    let results = request.results ?? []
                    continuation.resume(returning: results)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        let sorted = observations.sorted { lhs, rhs in
            lhs.boundingBox.width * lhs.boundingBox.height > rhs.boundingBox.width * rhs.boundingBox.height
        }

        var results: [ScanResult] = []
        for observation in sorted {
            guard let payload = observation.payloadStringValue, !payload.isEmpty,
                  let symbology = symbology(for: observation.symbology)
            else { continue }

            if case .recognized(let result) = ScanResultMapper.outcome(payload: payload, symbology: symbology),
               !results.contains(result) {
                results.append(result)
            }
        }

        guard !results.isEmpty else { throw DetectionError.nothingFound }
        return results
    }
}

extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
