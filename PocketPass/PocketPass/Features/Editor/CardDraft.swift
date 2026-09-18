import Foundation

/// The editable form state for adding or changing a card.
///
/// Kept apart from `WalletCard` because a half-filled form is not yet a valid card: the
/// payload may be incomplete and the expiry is a toggle plus a date rather than an optional.
struct CardDraft: Identifiable, Hashable {
    /// Identity of the *sheet*, not of the card; a new draft always opens a new sheet.
    let id = UUID()

    /// Set when editing an existing card, `nil` when adding one.
    var editingCardID: UUID?

    var name: String = ""
    var organization: String = ""
    var payload: String = ""
    var symbology: BarcodeSymbology = .qr
    var category: CardCategory = .loyalty
    var theme: CardTheme = .graphite
    var notes: String = ""
    var isFavorite: Bool = false
    var hasExpiration: Bool = false
    var expirationDate: Date = Date()

    private var createdAt: Date = Date()
    private var lastUsedAt: Date?

    /// A blank card typed in by hand.
    init(theme: CardTheme = .graphite, category: CardCategory = .loyalty) {
        self.theme = theme
        self.category = category
        self.symbology = category.defaultSymbology
    }

    /// A card started from a scan or a photo import.
    init(scan: ScanResult, theme: CardTheme = .graphite, category: CardCategory = .loyalty) {
        self.payload = scan.payload
        self.symbology = scan.symbology
        self.theme = theme
        self.category = category
    }

    /// An existing card opened for editing.
    init(card: WalletCard) {
        self.editingCardID = card.id
        self.name = card.name
        self.organization = card.organization
        self.payload = card.payload
        self.symbology = card.symbology
        self.category = card.category
        self.theme = card.theme
        self.notes = card.notes
        self.isFavorite = card.isFavorite
        self.hasExpiration = card.expirationDate != nil
        self.expirationDate = card.expirationDate ?? Date()
        self.createdAt = card.createdAt
        self.lastUsedAt = card.lastUsedAt
    }

    var isEditingExistingCard: Bool { editingCardID != nil }

    /// The validation error for the payload as typed, or `nil` when it is usable.
    var payloadError: BarcodeError? {
        do {
            _ = try BarcodeValidator.normalize(payload, for: symbology)
            return nil
        } catch let error as BarcodeError {
            return error
        } catch {
            return .renderingFailed
        }
    }

    var canSave: Bool { payloadError == nil }

    /// Builds the card to store, normalising the payload (adding a missing check digit, and so on).
    func makeCard() throws -> WalletCard {
        let normalizedPayload = try BarcodeValidator.normalize(payload, for: symbology)
        return WalletCard(
            id: editingCardID ?? UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            organization: organization.trimmingCharacters(in: .whitespacesAndNewlines),
            payload: normalizedPayload,
            symbology: symbology,
            category: category,
            theme: theme,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            isFavorite: isFavorite,
            expirationDate: hasExpiration ? expirationDate : nil,
            createdAt: createdAt,
            updatedAt: Date(),
            lastUsedAt: lastUsedAt
        )
    }
}
