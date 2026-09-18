import XCTest
@testable import PocketPass

final class WalletCardTests: XCTestCase {

    private func makeCard(
        name: String = "Clubcard",
        organization: String = "Tesco",
        payload: String = "5901234123457",
        symbology: BarcodeSymbology = .ean13,
        notes: String = "",
        expirationDate: Date? = nil
    ) -> WalletCard {
        WalletCard(
            name: name,
            organization: organization,
            payload: payload,
            symbology: symbology,
            notes: notes,
            expirationDate: expirationDate
        )
    }

    func testDisplayNameFallsBackToTheFormat() {
        XCTAssertEqual(makeCard(name: "  ").displayName, "EAN-13")
        XCTAssertEqual(makeCard(name: "Clubcard").displayName, "Clubcard")
    }

    func testNumericPayloadsAreGroupedForReading() {
        XCTAssertEqual(makeCard().humanReadablePayload, "5901 2341 2345 7")
    }

    func testFreeFormPayloadsAreNotRegrouped() {
        let card = makeCard(payload: "https://example.com/ticket", symbology: .qr)
        XCTAssertEqual(card.humanReadablePayload, "https://example.com/ticket")
    }

    func testSearchMatchesNameOrganizationNotesAndPayload() {
        let card = makeCard(notes: "Seat 14A")
        XCTAssertTrue(card.matches(query: "club"))
        XCTAssertTrue(card.matches(query: "TESCO"))
        XCTAssertTrue(card.matches(query: "14a"))
        XCTAssertTrue(card.matches(query: "590123"))
        XCTAssertTrue(card.matches(query: "   "), "an empty search shows everything")
        XCTAssertFalse(card.matches(query: "aeroplane"))
    }

    func testExpiry() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let yesterday = now.addingTimeInterval(-86_400)
        let inThreeDays = now.addingTimeInterval(3 * 86_400)
        let inTwoMonths = now.addingTimeInterval(60 * 86_400)

        XCTAssertTrue(makeCard(expirationDate: yesterday).isExpired(asOf: now))
        XCTAssertFalse(makeCard(expirationDate: inThreeDays).isExpired(asOf: now))
        XCTAssertFalse(makeCard().isExpired(asOf: now), "a card without an expiry never expires")

        XCTAssertTrue(makeCard(expirationDate: inThreeDays).isExpiringSoon(asOf: now))
        XCTAssertFalse(makeCard(expirationDate: inTwoMonths).isExpiringSoon(asOf: now))
        XCTAssertFalse(
            makeCard(expirationDate: yesterday).isExpiringSoon(asOf: now),
            "already expired is not 'expiring soon'"
        )
    }

    func testGroupingLeavesShortStringsAlone() {
        XCTAssertEqual("123".grouped(every: 4, separator: " "), "123")
        XCTAssertEqual("1234".grouped(every: 4, separator: " "), "1234")
        XCTAssertEqual("12345".grouped(every: 4, separator: " "), "1234 5")
        XCTAssertEqual("".grouped(every: 4, separator: " "), "")
    }

    func testCategoryDefaultsMatchTheirSymbology() {
        XCTAssertEqual(CardCategory.boardingPass.defaultSymbology, .aztec)
        XCTAssertEqual(CardCategory.loyalty.defaultSymbology, .code128)
    }

    func testDraftNormalisesThePayloadOnSave() throws {
        var draft = CardDraft()
        draft.symbology = .ean13
        draft.name = "  Clubcard  "
        // Spaced digits with the check digit still missing: what a card actually prints.
        draft.payload = "5901 2341 2345"

        let card = try draft.makeCard()

        XCTAssertEqual(card.payload, "5901234123457")
        XCTAssertEqual(card.name, "Clubcard")
        XCTAssertNil(card.expirationDate)
    }

    func testDraftKeepsTheIdentityOfTheCardBeingEdited() throws {
        let original = makeCard()
        var draft = CardDraft(card: original)
        draft.name = "Renamed"

        let card = try draft.makeCard()

        XCTAssertEqual(card.id, original.id)
        XCTAssertEqual(card.createdAt, original.createdAt)
        XCTAssertEqual(card.name, "Renamed")
    }

    func testDraftReportsAnInvalidPayload() {
        var draft = CardDraft()
        draft.symbology = .ean13
        draft.payload = "12"

        XCTAssertFalse(draft.canSave)
        XCTAssertEqual(draft.payloadError, .unsupportedDigitCount(accepted: [12, 13]))
        XCTAssertThrowsError(try draft.makeCard())
    }

    func testDraftFromAScanKeepsTheScannedFormat() {
        let draft = CardDraft(scan: ScanResult(payload: "036000291452", symbology: .upcA))
        XCTAssertEqual(draft.symbology, .upcA)
        XCTAssertEqual(draft.payload, "036000291452")
        XCTAssertTrue(draft.canSave)
        XCTAssertFalse(draft.isEditingExistingCard)
    }
}
