import XCTest
@testable import PocketPass

@MainActor
final class CardStoreTests: XCTestCase {

    private func makeCard(
        name: String = "Card",
        payload: String = "1234567890",
        symbology: BarcodeSymbology = .code128,
        category: CardCategory = .loyalty,
        isFavorite: Bool = false,
        lastUsedAt: Date? = nil
    ) -> WalletCard {
        WalletCard(
            name: name,
            payload: payload,
            symbology: symbology,
            category: category,
            isFavorite: isFavorite,
            lastUsedAt: lastUsedAt
        )
    }

    func testAddWritesThroughToTheRepository() {
        let repository = InMemoryCardRepository()
        let store = CardStore(repository: repository)

        store.add(makeCard(name: "Clubcard"))

        XCTAssertEqual(store.cards.count, 1)
        XCTAssertEqual(repository.storedCards.map(\.name), ["Clubcard"])
    }

    func testUpdateReplacesTheExistingCard() {
        let card = makeCard(name: "Old")
        let repository = InMemoryCardRepository(cards: [card])
        let store = CardStore(repository: repository)

        var edited = card
        edited.name = "New"
        store.update(edited)

        XCTAssertEqual(store.cards.count, 1)
        XCTAssertEqual(store.cards.first?.name, "New")
        XCTAssertEqual(repository.storedCards.first?.name, "New")
    }

    func testUpdateOfAnUnknownCardAddsIt() {
        let store = CardStore(repository: InMemoryCardRepository())
        store.update(makeCard(name: "Ghost"))
        XCTAssertEqual(store.cards.count, 1)
    }

    func testDelete() {
        let card = makeCard()
        let repository = InMemoryCardRepository(cards: [card])
        let store = CardStore(repository: repository)

        store.delete(card)

        XCTAssertTrue(store.cards.isEmpty)
        XCTAssertTrue(repository.storedCards.isEmpty)
    }

    func testFavouritesSortAboveEverythingElse() throws {
        let store = CardStore(repository: InMemoryCardRepository(cards: [
            makeCard(name: "Alpha", payload: "1"),
            makeCard(name: "Beta", payload: "2"),
        ]))

        let beta = try XCTUnwrap(store.cards.first { $0.name == "Beta" })
        store.toggleFavorite(beta)

        XCTAssertEqual(store.cards.map(\.name), ["Beta", "Alpha"])
    }

    func testRecentlyUsedCardsSortAboveUnusedOnes() throws {
        let store = CardStore(repository: InMemoryCardRepository(cards: [
            makeCard(name: "Alpha", payload: "1"),
            makeCard(name: "Zulu", payload: "2"),
        ]))

        let zulu = try XCTUnwrap(store.cards.first { $0.name == "Zulu" })
        store.markUsed(zulu)

        XCTAssertEqual(store.cards.map(\.name), ["Zulu", "Alpha"])
        XCTAssertNotNil(store.cards.first?.lastUsedAt)
    }

    func testFilteringByQueryAndCategory() {
        let store = CardStore(repository: InMemoryCardRepository(cards: [
            makeCard(name: "Clubcard", payload: "1", category: .loyalty),
            makeCard(name: "Gym", payload: "2", category: .membership),
            makeCard(name: "Flight to Lisbon", payload: "3", category: .boardingPass),
        ]))

        XCTAssertEqual(store.filteredCards(query: "gym").map(\.name), ["Gym"])
        XCTAssertEqual(store.filteredCards(query: "LISBON").map(\.name), ["Flight to Lisbon"])
        XCTAssertEqual(store.filteredCards(category: .loyalty).map(\.name), ["Clubcard"])
        XCTAssertEqual(store.filteredCards(query: "gym", category: .loyalty).count, 0)
        XCTAssertEqual(store.filteredCards().count, 3)
    }

    func testSearchAlsoMatchesThePayload() {
        let store = CardStore(repository: InMemoryCardRepository(cards: [
            makeCard(name: "Clubcard", payload: "5901234123457", symbology: .ean13),
        ]))
        XCTAssertEqual(store.filteredCards(query: "590123").count, 1)
    }

    func testExistingCardDetectsTheSameCodeInTheSameFormat() {
        let card = makeCard(payload: "ABC123", symbology: .code128)
        let store = CardStore(repository: InMemoryCardRepository(cards: [card]))

        XCTAssertNotNil(store.existingCard(payload: "ABC123", symbology: .code128))
        XCTAssertNil(store.existingCard(payload: "ABC123", symbology: .code39))
        XCTAssertNil(store.existingCard(payload: "ABC124", symbology: .code128))
    }

    func testMergeImportSkipsCardsAlreadyHeld() {
        let existing = makeCard(name: "Clubcard", payload: "ABC123")
        let store = CardStore(repository: InMemoryCardRepository(cards: [existing]))

        let added = store.importCards(
            [existing, makeCard(name: "New", payload: "XYZ789")],
            strategy: .merge
        )

        XCTAssertEqual(added, 1)
        XCTAssertEqual(store.cards.count, 2)
    }

    func testMergeImportGivesCollidingIdentifiersANewOne() {
        let existing = makeCard(name: "Clubcard", payload: "ABC123")
        let store = CardStore(repository: InMemoryCardRepository(cards: [existing]))

        // Same identifier, different code: a hand-edited backup can do this.
        var clash = existing
        clash.payload = "DIFFERENT"
        let added = store.importCards([clash], strategy: .merge)

        XCTAssertEqual(added, 1)
        XCTAssertEqual(Set(store.cards.map(\.id)).count, 2, "identifiers must stay unique")
    }

    func testReplaceImportDropsWhatWasThere() {
        let store = CardStore(repository: InMemoryCardRepository(cards: [makeCard(name: "Old")]))

        let count = store.importCards([makeCard(name: "Fresh", payload: "ZZZ")], strategy: .replace)

        XCTAssertEqual(count, 1)
        XCTAssertEqual(store.cards.map(\.name), ["Fresh"])
    }

    func testStorageFailureIsSurfacedRatherThanSwallowed() {
        let repository = InMemoryCardRepository()
        repository.saveError = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "disk full"])
        let store = CardStore(repository: repository)

        store.add(makeCard())

        XCTAssertNotNil(store.storageErrorMessage)
        XCTAssertTrue(store.storageErrorMessage?.contains("disk full") == true)
    }
}

final class FileCardRepositoryTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeRepository() -> FileCardRepository {
        FileCardRepository(fileURL: directory.appendingPathComponent("cards.json"))
    }

    func testLoadingBeforeAnythingIsSavedReturnsNoCards() throws {
        XCTAssertTrue(try makeRepository().load().isEmpty)
    }

    func testSaveThenLoadRoundTrip() throws {
        let repository = makeRepository()
        let card = WalletCard(
            name: "Clubcard",
            organization: "Tesco",
            payload: "5901234123457",
            symbology: .ean13,
            category: .loyalty,
            theme: .ocean,
            notes: "Till card",
            isFavorite: true,
            expirationDate: Date(timeIntervalSince1970: 1_800_000_000)
        )

        try repository.save([card])
        let loaded = try repository.load()

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.id, card.id)
        XCTAssertEqual(loaded.first?.name, "Clubcard")
        XCTAssertEqual(loaded.first?.symbology, .ean13)
        XCTAssertEqual(loaded.first?.theme, .ocean)
        XCTAssertEqual(loaded.first?.isFavorite, true)
        XCTAssertEqual(loaded.first?.expirationDate, card.expirationDate)
    }

    func testSavingCreatesTheContainingDirectory() throws {
        let nested = directory
            .appendingPathComponent("a/b/c", isDirectory: true)
            .appendingPathComponent("cards.json")
        let repository = FileCardRepository(fileURL: nested)

        try repository.save([WalletCard(name: "X", payload: "1", symbology: .qr)])

        XCTAssertTrue(FileManager.default.fileExists(atPath: nested.path))
    }

    func testCorruptFileThrows() throws {
        let url = directory.appendingPathComponent("cards.json")
        try Data("not json".utf8).write(to: url)

        XCTAssertThrowsError(try FileCardRepository(fileURL: url).load())
    }
}
