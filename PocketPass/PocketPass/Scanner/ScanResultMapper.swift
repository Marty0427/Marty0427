import AVFoundation
import Foundation

/// A code that was read from the camera or a photo.
struct ScanResult: Equatable {
    let payload: String
    let symbology: BarcodeSymbology
}

enum ScanOutcome: Equatable {
    case recognized(ScanResult)
    /// Read correctly, but PocketPass cannot draw this format again (e.g. Data Matrix).
    case unsupportedFormat(name: String)
    /// Read, but the payload does not make sense for the format.
    case unreadable(message: String)
}

/// Turns raw scanner output into something storable.
///
/// Kept free of UI so the fiddly parts — notably that AVFoundation reports UPC-A as a
/// 13 digit EAN — can be unit tested.
enum ScanResultMapper {

    /// Formats requested from the capture session. Data Matrix is included on purpose:
    /// it is better to tell someone the format is unsupported than to look broken.
    static let metadataObjectTypes: [AVMetadataObject.ObjectType] = [
        .qr, .aztec, .pdf417, .code128, .code39, .code39Mod43, .code93,
        .ean13, .ean8, .upce, .itf14, .interleaved2of5, .dataMatrix,
    ]

    static func symbology(for objectType: AVMetadataObject.ObjectType) -> BarcodeSymbology? {
        switch objectType {
        case .qr: return .qr
        case .aztec: return .aztec
        case .pdf417: return .pdf417
        case .code128: return .code128
        case .code39, .code39Mod43: return .code39
        case .ean13: return .ean13
        case .ean8: return .ean8
        case .upce: return .upcE
        case .itf14, .interleaved2of5: return .itf14
        default: return nil
        }
    }

    /// Readable name for a format that was recognised but cannot be stored.
    static func displayName(for objectType: AVMetadataObject.ObjectType) -> String {
        switch objectType {
        case .dataMatrix: return "Data Matrix"
        case .code93: return "Code 93"
        default: return objectType.rawValue
        }
    }

    static func outcome(payload: String, objectType: AVMetadataObject.ObjectType) -> ScanOutcome {
        guard let symbology = symbology(for: objectType) else {
            return .unsupportedFormat(name: displayName(for: objectType))
        }
        return outcome(payload: payload, symbology: symbology)
    }

    static func outcome(payload: String, symbology: BarcodeSymbology) -> ScanOutcome {
        let resolved = resolve(payload: payload, symbology: symbology)
        do {
            let normalized = try BarcodeValidator.normalize(resolved.payload, for: resolved.symbology)
            return .recognized(ScanResult(payload: normalized, symbology: resolved.symbology))
        } catch let error as BarcodeError {
            return .unreadable(message: error.errorDescription ?? "This code couldn’t be read.")
        } catch {
            return .unreadable(message: error.localizedDescription)
        }
    }

    /// AVFoundation and Vision both report UPC-A as an EAN-13 with a leading zero.
    /// Storing it as UPC-A keeps the number the same as the one printed on the card.
    static func resolve(payload: String, symbology: BarcodeSymbology) -> ScanResult {
        guard symbology == .ean13,
              payload.count == 13,
              payload.hasPrefix("0"),
              payload.allSatisfy(\.isASCIIDigit)
        else {
            return ScanResult(payload: payload, symbology: symbology)
        }
        return ScanResult(payload: String(payload.dropFirst()), symbology: .upcA)
    }
}
