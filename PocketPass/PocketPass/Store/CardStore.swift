import Foundation

/// The wallet itself: the single source of truth every screen observes.
@MainActor
final class CardStore: ObservableObject {

    /// How a restored backup is folded into what is already on the device.
    enum ImportStrategy {
        /// Keep existing cards, add the ones that are genuinely new.
        case merge
        /// Throw away what is stored and take the backup as-is.
        case replace
    }

    @Published private(set) var cards: [WalletCard] = []
    /// Set when reading or writing storage failed, so the UI can say so instead of losing data silently.
    @Published var storageErrorMessage: String?

    private let repository: CardRepository

    init(repository: CardRepository = FileCardRepository()) {
        self.repository = repository
        reload()
    }

    // MARK: - Reading

    func reload() {
        do {
            cards = sorted(try repository.load())
            storageErrorMessage = nil
        } catch {
            cards = []
            storageErrorMessage = "Your cards couldn’t be opened: \(error.localizedDescription)"
        }
    }

    var favorites: [WalletCard] {
        cards.filter(\.isFavorite)
    }

    func card(with id: UUID) -> WalletCard? {
        cards.first { $0.id == id }
    }

    /// Cards left after the search field and the category chip are applied.
    func filteredCards(query: String = "", category: CardCategory? = nil) -> [WalletCard] {
        cards.filter { card in
            (category == nil || card.category == category) && card.matches(query: query)
        }
    }

    /// An existing card holding the same code, used to warn before saving a duplicate.
    func existingCard(payload: String, symbology: BarcodeSymbology) -> WalletCard? {
        cards.first { $0.payload == payload && $0.symbology == symbology }
    }

    // MARK: - Writing

    func add(_ card: WalletCard) {
        var card = card
        card.updatedAt = Date()
        cards.append(card)
        persist()
    }

    func update(_ card: WalletCard) {
        guard let index = cards.firstIndex(where: { $0.id == card.id }) else {
            add(card)
            return
        }
        var updated = card
        updated.updatedAt = Date()
        cards[index] = updated
        persist()
    }

    func delete(_ card: WalletCard) {
        delete(ids: [card.id])
    }

    func delete(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        cards.removeAll { ids.contains($0.id) }
        persist()
    }

    func toggleFavorite(_ card: WalletCard) {
        guard let index = cards.firstIndex(where: { $0.id == card.id }) else { return }
        cards[index].isFavorite.toggle()
        cards[index].updatedAt = Date()
        persist()
    }

    /// Records that a card was just shown at a till, which floats it back to the top.
    func markUsed(_ card: WalletCard, at date: Date = Date()) {
        guard let index = cards.firstIndex(where: { $0.id == card.id }) else { return }
        cards[index].lastUsedAt = date
        persist()
    }

    @discardableResult
    func importCards(_ incoming: [WalletCard], strategy: ImportStrategy) -> Int {
        switch strategy {
        case .replace:
            cards = incoming
            persist()
            return incoming.count
        case .merge:
            var added = 0
            for card in incoming {
                // Same code in the same format is the same pass, however it is named.
                if existingCard(payload: card.payload, symbology: card.symbology) != nil { continue }
                var card = card
                if cards.contains(where: { $0.id == card.id }) { card.id = UUID() }
                cards.append(card)
                added += 1
            }
            if added > 0 { persist() }
            return added
        }
    }

    /// The colour proposed for the next card of this kind.
    func suggestedTheme(for category: CardCategory) -> CardTheme {
        CardTheme.suggested(for: category, existingCount: cards.count)
    }

    // MARK: - Private

    private func persist() {
        cards = sorted(cards)
        do {
            try repository.save(cards)
            storageErrorMessage = nil
        } catch {
            storageErrorMessage = "Your change couldn’t be saved: \(error.localizedDescription)"
        }
    }

    /// Favourites first, then the passes used most recently, then alphabetical.
    private func sorted(_ cards: [WalletCard]) -> [WalletCard] {
        cards.sorted { lhs, rhs in
            if lhs.isFavorite != rhs.isFavorite { return lhs.isFavorite }
            switch (lhs.lastUsedAt, rhs.lastUsedAt) {
            case let (left?, right?) where left != right:
                return left > right
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            default:
                break
            }
            let comparison = lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
            if comparison != .orderedSame { return comparison == .orderedAscending }
            return lhs.createdAt < rhs.createdAt
        }
    }
}
