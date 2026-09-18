import XCTest
@testable import PocketPass

final class BarcodeValidatorTests: XCTestCase {

    // MARK: - GTIN check digits

    func testEAN13AppendsMissingCheckDigit() throws {
        let normalized = try BarcodeValidator.normalize("590123412345", for: .ean13)
        XCTAssertEqual(normalized, "5901234123457")
    }

    func testEAN13AcceptsCorrectCheckDigit() throws {
        XCTAssertEqual(try BarcodeValidator.normalize("5901234123457", for: .ean13), "5901234123457")
    }

    func testEAN13RejectsWrongCheckDigit() {
        XCTAssertThrowsError(try BarcodeValidator.normalize("5901234123454", for: .ean13)) { error in
            XCTAssertEqual(error as? BarcodeError, .invalidCheckDigit(expected: "7"))
        }
    }

    func testEAN8CheckDigit() throws {
        // 9638-5074 is the canonical EAN-8 example.
        XCTAssertEqual(try BarcodeValidator.normalize("9638507", for: .ean8), "96385074")
    }

    func testUPCACheckDigit() throws {
        XCTAssertEqual(try BarcodeValidator.normalize("03600029145", for: .upcA), "036000291452")
    }

    func testITF14CheckDigit() throws {
        XCTAssertEqual(try BarcodeValidator.normalize("1540141253220", for: .itf14), "15401412532202")
    }

    func testCheckDigitOfAllZeroBodyIsZero() {
        XCTAssertEqual(BarcodeValidator.checkDigit(forBody: "000000000000"), "0")
    }

    // MARK: - Input cleaning

    func testSeparatorsAreStripped() throws {
        XCTAssertEqual(try BarcodeValidator.normalize("5901 2341 2345 7", for: .ean13), "5901234123457")
        XCTAssertEqual(try BarcodeValidator.normalize("5901-2341-23457", for: .ean13), "5901234123457")
    }

    func testWrongDigitCountIsRejected() {
        XCTAssertThrowsError(try BarcodeValidator.normalize("12345", for: .ean13)) { error in
            XCTAssertEqual(error as? BarcodeError, .unsupportedDigitCount(accepted: [12, 13]))
        }
    }

    func testLettersAreRejectedForNumericFormats() {
        XCTAssertThrowsError(try BarcodeValidator.normalize("59012341234A", for: .ean13)) { error in
            XCTAssertEqual(error as? BarcodeError, .nonNumericPayload)
        }
    }

    func testEmptyPayloadIsRejected() {
        XCTAssertThrowsError(try BarcodeValidator.normalize("   ", for: .qr)) { error in
            XCTAssertEqual(error as? BarcodeError, .emptyPayload)
        }
    }

    // MARK: - UPC-E

    func testUPCEExpandsToUPCA() throws {
        // Case X6 in 5...9: 0 12345 0000 6, check digit 5.
        XCTAssertEqual(try BarcodeValidator.upcAEquivalent(ofUPCE: "01234565"), "012345000065")
    }

    func testUPCEExpansionForTrailingZero() throws {
        // Case X6 in 0...2: manufacturer digits move, then four zeroes.
        XCTAssertEqual(try BarcodeValidator.upcAEquivalent(ofUPCE: "0425261"), "042100005264")
    }

    func testUPCEAddsCheckDigitToSixDigits() throws {
        let normalized = try BarcodeValidator.normalize("123456", for: .upcE)
        XCTAssertEqual(normalized.count, 8)
        XCTAssertTrue(normalized.hasPrefix("0123456"))
    }

    func testUPCERejectsBadNumberSystem() {
        XCTAssertThrowsError(try BarcodeValidator.normalize("2123456", for: .upcE))
    }

    // MARK: - Character sets

    func testCode39UppercasesInput() throws {
        XCTAssertEqual(try BarcodeValidator.normalize("member-42", for: .code39), "MEMBER-42")
    }

    func testCode39RejectsUnsupportedCharacter() {
        XCTAssertThrowsError(try BarcodeValidator.normalize("member#42", for: .code39)) { error in
            XCTAssertEqual(error as? BarcodeError, .unsupportedCharacter("#"))
        }
    }

    func testCode128RejectsNonASCII() {
        XCTAssertThrowsError(try BarcodeValidator.normalize("café", for: .code128)) { error in
            XCTAssertEqual(error as? BarcodeError, .unsupportedEncoding("Code 128"))
        }
    }

    func testQRAcceptsUnicodeAndTrimsWhitespace() throws {
        XCTAssertEqual(try BarcodeValidator.normalize("  café ☕️\n", for: .qr), "café ☕️")
    }

    func testOverlongPayloadIsRejected() {
        let long = String(repeating: "A", count: BarcodeSymbology.code39.maximumPayloadLength + 1)
        XCTAssertThrowsError(try BarcodeValidator.normalize(long, for: .code39)) { error in
            XCTAssertEqual(
                error as? BarcodeError,
                .payloadTooLong(limit: BarcodeSymbology.code39.maximumPayloadLength)
            )
        }
    }

    func testIsValidMirrorsNormalize() {
        XCTAssertTrue(BarcodeValidator.isValid("5901234123457", for: .ean13))
        XCTAssertFalse(BarcodeValidator.isValid("5901234123450", for: .ean13))
    }
}
