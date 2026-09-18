import Foundation

/// A single stored pass: the scannable payload plus everything needed to find and show it again.
struct WalletCard: Identifiable, Codable, Hashable {
    var id: UUID
    /// What the owner calls it, e.g. "Tesco Clubcard".
    var name: String
    /// Issuer or venue, shown as the card subtitle.
    var organization: String
    /// The exact string that was scanned or typed; this is what gets re-encoded.
    var payload: String
    var symbology: BarcodeSymbology
    var category: CardCategory
    var theme: CardTheme
    var notes: String
    var isFavorite: Bool
    var expirationDate: Date?
    var createdAt: Date
    var updatedAt: Date
    var lastUsedAt: Date?

    init(
        id: UUID = UUID(),
        name: String,
        organization: String = "",
        payload: String,
        symbology: BarcodeSymbology,
        category: CardCategory = .loyalty,
        theme: CardTheme = .graphite,
        notes: String = "",
        isFavorite: Bool = false,
        expirationDate: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastUsedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.organization = organization
        self.payload = payload
        self.symbology = symbology
        self.category = category
        self.theme = theme
        self.notes = notes
        self.isFavorite = isFavorite
        self.expirationDate = expirationDate
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastUsedAt = lastUsedAt
    }

    /// Title fallback so a card is never nameless in the list.
    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? symbology.displayName : trimmed
    }

    /// The payload as printed under the bars: digits grouped for numeric formats, otherwise raw.
    var humanReadablePayload: String {
        guard symbology.isNumericOnly else { return payload }
        return payload.grouped(every: 4, separator: " ")
    }

    func isExpired(asOf date: Date = Date()) -> Bool {
        guard let expirationDate else { return false }
        return expirationDate < date
    }

    /// True while the pass is still valid but close enough to expiry to warn about.
    func isExpiringSoon(asOf date: Date = Date(), within days: Int = 7) -> Bool {
        guard let expirationDate, expirationDate >= date else { return false }
        guard let limit = Calendar.current.date(byAdding: .day, value: days, to: date) else { return false }
        return expirationDate <= limit
    }

    /// Free-text haystack used by the search field.
    func matches(query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        let haystack = [name, organization, notes, payload, category.displayName].joined(separator: "\n")
        return haystack.localizedCaseInsensitiveContains(needle)
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case id, name, organization, payload, symbology, category, theme
        case notes, isFavorite, expirationDate, createdAt, updatedAt, lastUsedAt
    }

    /// Decoding is deliberately forgiving: a backup written by a newer build, or one that a
    /// person hand-edited, should still restore instead of failing the whole file.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        organization = try container.decodeIfPresent(String.self, forKey: .organization) ?? ""
        payload = try container.decode(String.self, forKey: .payload)
        symbology = try container.decodeIfPresent(BarcodeSymbology.self, forKey: .symbology) ?? .qr
        category = try container.decodeIfPresent(CardCategory.self, forKey: .category) ?? .other
        theme = try container.decodeIfPresent(CardTheme.self, forKey: .theme) ?? .graphite
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        expirationDate = try container.decodeIfPresent(Date.self, forKey: .expirationDate)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        lastUsedAt = try container.decodeIfPresent(Date.self, forKey: .lastUsedAt)
    }
}

extension String {
    /// Inserts `separator` every `size` characters, used for readable digit runs.
    func grouped(every size: Int, separator: String) -> String {
        guard size > 0, count > size else { return self }
        var result: [String] = []
        var index = startIndex
        while index < endIndex {
            let next = self.index(index, offsetBy: size, limitedBy: endIndex) ?? endIndex
            result.append(String(self[index..<next]))
            index = next
        }
        return result.joined(separator: separator)
    }
}
