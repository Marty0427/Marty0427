import Foundation

/// The kind of pass a card holds. Drives grouping, the default symbology and the icon.
enum CardCategory: String, Codable, CaseIterable, Identifiable, Hashable {
    case loyalty
    case boardingPass
    case eventTicket
    case transit
    case membership
    case giftCard
    case coupon
    case identification
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .loyalty: return "Loyalty"
        case .boardingPass: return "Boarding Pass"
        case .eventTicket: return "Event Ticket"
        case .transit: return "Transit"
        case .membership: return "Membership"
        case .giftCard: return "Gift Card"
        case .coupon: return "Coupon"
        case .identification: return "ID"
        case .other: return "Other"
        }
    }

    var symbolName: String {
        switch self {
        case .loyalty: return "cart"
        case .boardingPass: return "airplane"
        case .eventTicket: return "ticket"
        case .transit: return "tram.fill"
        case .membership: return "person.text.rectangle"
        case .giftCard: return "gift"
        case .coupon: return "tag"
        case .identification: return "person.crop.rectangle"
        case .other: return "rectangle.on.rectangle"
        }
    }

    /// Format pre-selected when someone adds a card of this kind by hand.
    var defaultSymbology: BarcodeSymbology {
        switch self {
        case .boardingPass: return .aztec
        case .loyalty, .giftCard: return .code128
        case .eventTicket, .transit, .membership, .coupon, .identification, .other: return .qr
        }
    }

    /// Passes that usually stop being useful once they expire, so the UI can nudge about it.
    var isTimeSensitive: Bool {
        switch self {
        case .boardingPass, .eventTicket, .transit, .coupon:
            return true
        case .loyalty, .membership, .giftCard, .identification, .other:
            return false
        }
    }
}
