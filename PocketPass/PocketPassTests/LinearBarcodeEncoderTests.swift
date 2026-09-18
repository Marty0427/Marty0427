import XCTest
@testable import PocketPass

final class LinearBarcodeEncoderTests: XCTestCase {

    // MARK: - Encoding table invariants
    //
    // These check the EAN tables against the rules the standard defines, so a typo in a
    // transcribed pattern fails here rather than at a supermarket till.

    func testEveryEANPatternIsSevenModules() {
        for patterns in [
            LinearBarcodeEncoder.leftOddPatterns,
            LinearBarcodeEncoder.leftEvenPatterns,
            LinearBarcodeEncoder.rightPatterns,
        ] {
            XCTAssertEqual(patterns.count, 10)
            for pattern in patterns {
                XCTAssertEqual(pattern.count, 7, "\(pattern) is not seven modules")
            }
        }
    }

    func testRightPatternsAreTheComplementOfLeftOddPatterns() {
        for digit in 0...9 {
            let complement = String(LinearBarcodeEncoder.leftOddPatterns[digit].map { $0 == "0" ? "1" : "0" })
            XCTAssertEqual(complement, LinearBarcodeEncoder.rightPatterns[digit], "digit \(digit)")
        }
    }

    func testLeftEvenPatternsAreReversedRightPatterns() {
        for digit in 0...9 {
            let reversed = String(LinearBarcodeEncoder.rightPatterns[digit].reversed())
            XCTAssertEqual(reversed, LinearBarcodeEncoder.leftEvenPatterns[digit], "digit \(digit)")
        }
    }

    func testLeftPatternParity() {
        for digit in 0...9 {
            let oddBars = LinearBarcodeEncoder.leftOddPatterns[digit].filter { $0 == "1" }.count
            XCTAssertEqual(oddBars % 2, 1, "L pattern for \(digit) must have odd parity")

            let evenBars = LinearBarcodeEncoder.leftEvenPatterns[digit].filter { $0 == "1" }.count
            XCTAssertEqual(evenBars % 2, 0, "G pattern for \(digit) must have even parity")
        }
    }

    func testPatternsAreUnique() {
        XCTAssertEqual(Set(LinearBarcodeEncoder.leftOddPatterns).count, 10)
        XCTAssertEqual(Set(LinearBarcodeEncoder.leftEvenPatterns).count, 10)
        XCTAssertEqual(Set(LinearBarcodeEncoder.rightPatterns).count, 10)
        XCTAssertEqual(Set(LinearBarcodeEncoder.parityPatterns).count, 10)
    }

    func testParityPatternsStartWithOddAndAreSixLong() {
        for (digit, pattern) in LinearBarcodeEncoder.parityPatterns.enumerated() {
            XCTAssertEqual(pattern.count, 6, "digit \(digit)")
            XCTAssertTrue(pattern.hasPrefix("O"), "digit \(digit)")
            XCTAssertTrue(pattern.allSatisfy { $0 == "O" || $0 == "E" }, "digit \(digit)")
        }
    }

    func testCode39PatternsAreTwelveModulesWithThreeWideElements() {
        for (character, pattern) in LinearBarcodeEncoder.code39Patterns {
            XCTAssertEqual(pattern.count, 12, "\(character)")

            // Nine elements per character, exactly three of them wide.
            let runs = runLengths(of: pattern)
            XCTAssertEqual(runs.count, 9, "\(character) must have nine elements")
            XCTAssertEqual(runs.filter { $0 == 2 }.count, 3, "\(character) must have three wide elements")
            XCTAssertTrue(runs.allSatisfy { $0 == 1 || $0 == 2 }, "\(character) has an invalid element width")
        }
    }

    func testCode39CoversTheAdvertisedAlphabet() {
        for character in BarcodeValidator.code39Alphabet {
            XCTAssertNotNil(LinearBarcodeEncoder.code39Patterns[character], "missing pattern for \(character)")
        }
    }

    func testITFPatternsHaveTwoWideElements() {
        XCTAssertEqual(LinearBarcodeEncoder.itfPatterns.count, 10)
        for (digit, widths) in LinearBarcodeEncoder.itfPatterns.enumerated() {
            XCTAssertEqual(widths.count, 5, "digit \(digit)")
            XCTAssertEqual(widths.filter { $0 == 2 }.count, 2, "digit \(digit) must have two wide elements")
            XCTAssertEqual(widths.reduce(0, +), 7, "digit \(digit)")
        }
    }

    // MARK: - Assembled symbols

    func testEAN13HasGuardsInTheRightPlaces() throws {
        let barcode = try LinearBarcodeEncoder.encode("5901234123457", symbology: .ean13)
        XCTAssertEqual(barcode.moduleCount, 95)
        XCTAssertEqual(bits(barcode.modules[0..<3]), "101")
        XCTAssertEqual(bits(barcode.modules[45..<50]), "01010")
        XCTAssertEqual(bits(barcode.modules[92..<95]), "101")
    }

    func testEAN13CarriesTheFirstDigitInTheParityOfTheLeftHalf() throws {
        let leadingZero = try LinearBarcodeEncoder.encode("0012345678905", symbology: .ean13)
        let leadingNine = try LinearBarcodeEncoder.encode("9012345678906", symbology: .ean13)

        // Digits 2-7 are "012345" in both numbers, yet their left halves differ: that
        // difference is exactly how the leading digit is carried.
        XCTAssertNotEqual(bits(leadingZero.modules[3..<45]), bits(leadingNine.modules[3..<45]))

        // A leading zero means all-odd parity, so the left half is the plain L patterns.
        let digits = "0012345678905".compactMap(\.wholeNumberValue)
        let expected = digits[1...6].map { LinearBarcodeEncoder.leftOddPatterns[$0] }.joined()
        XCTAssertEqual(bits(leadingZero.modules[3..<45]), expected)
    }

    func testEAN8ModuleCount() throws {
        let barcode = try LinearBarcodeEncoder.encode("96385074", symbology: .ean8)
        XCTAssertEqual(barcode.moduleCount, 67)
        XCTAssertEqual(bits(barcode.modules[0..<3]), "101")
        XCTAssertEqual(bits(barcode.modules[31..<36]), "01010")
    }

    func testUPCAIsTheSameSymbolAsEAN13WithALeadingZero() throws {
        let upc = try LinearBarcodeEncoder.encode("036000291452", symbology: .upcA)
        let ean = try LinearBarcodeEncoder.encode("0036000291452", symbology: .ean13)
        XCTAssertEqual(upc.modules, ean.modules)
        XCTAssertEqual(upc.humanReadable, "036000291452", "the printed digits stay in UPC form")
    }

    func testUPCEIsDrawnAsItsUPCAExpansion() throws {
        let upce = try LinearBarcodeEncoder.encode("01234565", symbology: .upcE)
        let expansion = try LinearBarcodeEncoder.encode("012345000065", symbology: .upcA)
        XCTAssertEqual(upce.modules, expansion.modules)
        XCTAssertEqual(upce.humanReadable, "01234565")
    }

    func testCode39WrapsThePayloadInStartAndStopCharacters() throws {
        let barcode = try LinearBarcodeEncoder.encode("A", symbology: .code39)
        // Three characters at twelve modules each, plus two narrow separators.
        XCTAssertEqual(barcode.moduleCount, 3 * 12 + 2)

        let start = LinearBarcodeEncoder.code39Patterns["*"]!
        XCTAssertEqual(bits(barcode.modules[0..<12]), start)
        XCTAssertEqual(bits(barcode.modules[(barcode.moduleCount - 12)..<barcode.moduleCount]), start)
    }

    func testITF14ModuleCount() throws {
        let barcode = try LinearBarcodeEncoder.encode("15401412532202", symbology: .itf14)
        // Start (4) + seven digit pairs (14 each) + stop (4).
        XCTAssertEqual(barcode.moduleCount, 4 + 7 * 14 + 4)
        XCTAssertEqual(bits(barcode.modules[0..<4]), "1010")
        XCTAssertEqual(bits(barcode.modules[(barcode.moduleCount - 4)..<barcode.moduleCount]), "1101")
    }

    func testEncoderRejectsMatrixSymbologies() {
        for symbology in [BarcodeSymbology.qr, .aztec, .pdf417, .code128] {
            XCTAssertThrowsError(try LinearBarcodeEncoder.encode("12345", symbology: symbology))
        }
    }

    func testEverySymbologyHasExactlyOneEngine() {
        for symbology in BarcodeSymbology.allCases {
            let linear = LinearBarcodeEncoder.supported.contains(symbology)
            let coreImage = CoreImageBarcodeGenerator.supported.contains(symbology)
            XCTAssertTrue(linear != coreImage, "\(symbology.displayName) needs exactly one renderer")
        }
    }

    // MARK: - Helpers

    private func bits(_ modules: ArraySlice<Bool>) -> String {
        String(modules.map { $0 ? "1" : "0" })
    }

    private func runLengths(of pattern: String) -> [Int] {
        var runs: [Int] = []
        var current: Character?
        var length = 0
        for character in pattern {
            if character == current {
                length += 1
            } else {
                if current != nil { runs.append(length) }
                current = character
                length = 1
            }
        }
        if current != nil { runs.append(length) }
        return runs
    }
}
