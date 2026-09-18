import SwiftUI

/// A fixed palette of card colours. Stored by name so the palette can be re-tuned later
/// (including for dark mode) without migrating any saved data.
enum CardTheme: String, Codable, CaseIterable, Identifiable, Hashable {
    case graphite
    case ocean
    case forest
    case sunset
    case berry
    case sand
    case plum
    case slate

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .graphite: return "Graphite"
        case .ocean: return "Ocean"
        case .forest: return "Forest"
        case .sunset: return "Sunset"
        case .berry: return "Berry"
        case .sand: return "Sand"
        case .plum: return "Plum"
        case .slate: return "Slate"
        }
    }

    private var hexPair: (start: UInt32, end: UInt32) {
        switch self {
        case .graphite: return (0x3A3A3C, 0x1C1C1E)
        case .ocean: return (0x1B6CA8, 0x0C3D63)
        case .forest: return (0x2E7D4F, 0x14532D)
        case .sunset: return (0xE4572E, 0x9B2226)
        case .berry: return (0xC2185B, 0x7B1140)
        case .sand: return (0xC8922E, 0x8A5A16)
        case .plum: return (0x6D3B9E, 0x3F2069)
        case .slate: return (0x4A6572, 0x233640)
        }
    }

    var startColor: Color { Color(hex: hexPair.start) }
    var endColor: Color { Color(hex: hexPair.end) }

    var gradient: LinearGradient {
        LinearGradient(
            colors: [startColor, endColor],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Colour used for text and icons drawn on top of the gradient.
    var foregroundColor: Color { .white }

    /// A stable but varied default so a wallet full of cards is not a wall of one colour.
    static func suggested(for category: CardCategory, existingCount: Int) -> CardTheme {
        switch category {
        case .boardingPass: return .ocean
        case .eventTicket: return .berry
        case .transit: return .forest
        case .giftCard: return .sunset
        case .identification: return .slate
        case .loyalty, .membership, .coupon, .other:
            let palette = CardTheme.allCases
            return palette[abs(existingCount) % palette.count]
        }
    }
}

extension Color {
    init(hex: UInt32) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }
}
