import CoreGraphics
import Foundation

/// The barcode formats PocketPass can both scan and re-render on screen.
///
/// Only symbologies that can be rendered back to the screen are listed here: a pass is
/// useless if the app can store the payload but cannot show a scannable code at the till.
enum BarcodeSymbology: String, Codable, CaseIterable, Identifiable, Hashable {
    case qr
    case aztec
    case pdf417
    case code128
    case code39
    case ean13
    case ean8
    case upcA
    case upcE
    case itf14

    var id: String { rawValue }

    enum Dimension {
        /// Bars and spaces along a single axis (EAN-13, Code 128, ...).
        case linear
        /// Two dimensional matrix codes (QR, Aztec, PDF417).
        case matrix
    }

    var dimension: Dimension {
        switch self {
        case .qr, .aztec, .pdf417:
            return .matrix
        case .code128, .code39, .ean13, .ean8, .upcA, .upcE, .itf14:
            return .linear
        }
    }

    var displayName: String {
        switch self {
        case .qr: return "QR Code"
        case .aztec: return "Aztec"
        case .pdf417: return "PDF417"
        case .code128: return "Code 128"
        case .code39: return "Code 39"
        case .ean13: return "EAN-13"
        case .ean8: return "EAN-8"
        case .upcA: return "UPC-A"
        case .upcE: return "UPC-E"
        case .itf14: return "ITF-14"
        }
    }

    /// A short hint shown next to the format picker so people can pick without knowing the jargon.
    var usageHint: String {
        switch self {
        case .qr: return "Loyalty apps, event tickets, Wi-Fi and links"
        case .aztec: return "Boarding passes and rail tickets"
        case .pdf417: return "Boarding passes, IDs and driving licences"
        case .code128: return "Membership and shipping labels"
        case .code39: return "Older membership and badge systems"
        case .ean13: return "Retail loyalty cards (13 digits)"
        case .ean8: return "Short retail codes (8 digits)"
        case .upcA: return "North American retail (12 digits)"
        case .upcE: return "Compressed UPC (6-8 digits)"
        case .itf14: return "Cartons and wholesale cards (14 digits)"
        }
    }

    /// Width divided by height used when laying the code out on the card detail screen.
    var preferredAspectRatio: CGFloat {
        switch self {
        case .qr, .aztec: return 1
        case .pdf417: return 2.6
        case .code128, .code39, .itf14: return 2.4
        case .ean13, .upcA: return 1.9
        case .ean8, .upcE: return 1.6
        }
    }

    /// `true` when the payload may only contain decimal digits.
    var isNumericOnly: Bool {
        switch self {
        case .ean13, .ean8, .upcA, .upcE, .itf14:
            return true
        case .qr, .aztec, .pdf417, .code128, .code39:
            return false
        }
    }

    /// Digit counts accepted by the editor, including forms where the check digit is still missing.
    /// Empty for symbologies that accept free-form payloads.
    var acceptedDigitCounts: [Int] {
        switch self {
        case .ean13: return [12, 13]
        case .ean8: return [7, 8]
        case .upcA: return [11, 12]
        case .upcE: return [6, 7, 8]
        case .itf14: return [13, 14]
        case .qr, .aztec, .pdf417, .code128, .code39: return []
        }
    }

    /// Maximum payload length the renderer will attempt, keeping generated symbols readable.
    var maximumPayloadLength: Int {
        switch self {
        case .qr: return 1_200
        case .aztec: return 1_000
        case .pdf417: return 1_100
        case .code128: return 80
        case .code39: return 40
        case .ean13, .ean8, .upcA, .upcE, .itf14: return 14
        }
    }

    /// Formats offered first in the editor, because they cover most wallets.
    static var commonlyUsed: [BarcodeSymbology] {
        [.qr, .aztec, .pdf417, .code128, .ean13, .code39]
    }
}
