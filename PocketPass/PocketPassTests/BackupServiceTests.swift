import XCTest
@testable import PocketPass

final class BackupServiceTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private var sampleCards: [WalletCard] {
        [
            WalletCard(name: "Clubcard", payload: "5901234123457", symbology: .ean13),
            WalletCard(name: "Gym", payload: "MEMBER-42", symbology: .code39, category: .membership),
        ]
    }

    func testWriteThenReadRoundTrip() throws {
        let url = try BackupService.writeBackup(cards: sampleCards, in: directory)
        let restored = try BackupService.readBackup(at: url)

        XCTAssertEqual(restored.map(\.name), ["Clubcard", "Gym"])
        XCTAssertEqual(restored.map(\.payload), ["5901234123457", "MEMBER-42"])
    }

    func testBackupFileIsNamedByDate() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let url = try BackupService.writeBackup(cards: [], in: directory, date: date)
        XCTAssertTrue(url.lastPathComponent.hasSuffix(".json"), url.lastPathComponent)
        XCTAssertTrue(url.lastPathComponent.hasPrefix("PocketPass-"), url.lastPathComponent)
    }

    func testABareArrayOfCardsAlsoRestores() throws {
        // Someone trimming the file by hand is a case worth surviving.
        let data = try CardCoding.encoder.encode(sampleCards)
        let restored = try BackupService.readBackup(from: data)
        XCTAssertEqual(restored.count, 2)
    }

    func testPartialCardsFallBackToDefaults() throws {
        let json = """
        [{ "payload": "ABC123" }]
        """
        let restored = try BackupService.readBackup(from: Data(json.utf8))

        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(restored.first?.payload, "ABC123")
        XCTAssertEqual(restored.first?.symbology, .qr)
        XCTAssertEqual(restored.first?.category, .other)
        XCTAssertEqual(restored.first?.theme, .graphite)
    }

    func testCardWithoutAPayloadIsRejected() {
        let json = """
        [{ "name": "No code here" }]
        """
        XCTAssertThrowsError(try BackupService.readBackup(from: Data(json.utf8)))
    }
}
