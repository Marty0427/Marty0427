import AVFoundation
import XCTest
@testable import PocketPass

final class ScanResultMapperTests: XCTestCase {

    func testQRCodePassesStraightThrough() {
        let outcome = ScanResultMapper.outcome(payload: "https://example.com", objectType: .qr)
        XCTAssertEqual(outcome, .recognized(ScanResult(payload: "https://example.com", symbology: .qr)))
    }

    func testEAN13WithLeadingZeroBecomesUPCA() {
        // AVFoundation reports UPC-A as a 13 digit EAN, but the card is printed as 12 digits.
        let outcome = ScanResultMapper.outcome(payload: "0036000291452", objectType: .ean13)
        XCTAssertEqual(outcome, .recognized(ScanResult(payload: "036000291452", symbology: .upcA)))
    }

    func testGenuineEAN13IsLeftAlone() {
        let outcome = ScanResultMapper.outcome(payload: "5901234123457", objectType: .ean13)
        XCTAssertEqual(outcome, .recognized(ScanResult(payload: "5901234123457", symbology: .ean13)))
    }

    func testCode39WithChecksumMapsToCode39() {
        let outcome = ScanResultMapper.outcome(payload: "MEMBER-42", objectType: .code39Mod43)
        XCTAssertEqual(outcome, .recognized(ScanResult(payload: "MEMBER-42", symbology: .code39)))
    }

    func testUnsupportedFormatIsReportedRatherThanStored() {
        let outcome = ScanResultMapper.outcome(payload: "anything", objectType: .dataMatrix)
        XCTAssertEqual(outcome, .unsupportedFormat(name: "Data Matrix"))
    }

    func testPayloadThatFailsValidationIsReportedAsUnreadable() {
        // A 13 digit "EAN" whose check digit is wrong cannot be re-drawn faithfully.
        let outcome = ScanResultMapper.outcome(payload: "5901234123451", objectType: .ean13)
        guard case .unreadable = outcome else {
            return XCTFail("expected an unreadable outcome, got \(outcome)")
        }
    }

    func testRequestedMetadataTypesCoverEverythingWeCanStore() {
        let storable = ScanResultMapper.metadataObjectTypes.compactMap(ScanResultMapper.symbology(for:))
        for symbology in BarcodeSymbology.allCases where symbology != .upcA {
            // UPC-A has no metadata type of its own; it arrives as an EAN-13.
            XCTAssertTrue(storable.contains(symbology), "no scanner type maps to \(symbology.displayName)")
        }
    }

    func testResolveLeavesShortNumbersAlone() {
        let result = ScanResultMapper.resolve(payload: "012345", symbology: .ean13)
        XCTAssertEqual(result, ScanResult(payload: "012345", symbology: .ean13))
    }
}
