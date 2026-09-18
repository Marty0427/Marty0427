import Foundation

/// A one dimensional barcode expressed as modules: `true` is a bar, `false` is a space.
/// The quiet zone is *not* included; the renderer adds it.
struct LinearBarcode: Equatable {
    let modules: [Bool]
    /// The digits or characters printed underneath the symbol.
    let humanReadable: String

    var moduleCount: Int { modules.count }
}

/// Encoder for the linear symbologies Core Image cannot generate itself
/// (Core Image only ships a Code 128 generator).
///
/// Wide elements use a 2:1 ratio, which is inside the 2:1-3:1 range every reader accepts.
enum LinearBarcodeEncoder {

    /// Symbologies this type knows how to encode.
    static let supported: Set<BarcodeSymbology> = [.ean13, .ean8, .upcA, .upcE, .itf14, .code39]

    static func encode(_ rawPayload: String, symbology: BarcodeSymbology) throws -> LinearBarcode {
        let payload = try BarcodeValidator.normalize(rawPayload, for: symbology)

        switch symbology {
        case .ean13:
            return LinearBarcode(modules: try encodeEAN13(payload), humanReadable: payload)
        case .upcA:
            // UPC-A is EAN-13 with a leading zero and identical bars.
            return LinearBarcode(modules: try encodeEAN13("0" + payload), humanReadable: payload)
        case .upcE:
            // The compressed UPC-E symbol carries the same GTIN as its UPC-A expansion, and
            // every till expands it on read, so the expansion is what gets drawn.
            let expanded = try BarcodeValidator.upcAEquivalent(ofUPCE: payload)
            return LinearBarcode(modules: try encodeEAN13("0" + expanded), humanReadable: payload)
        case .ean8:
            return LinearBarcode(modules: try encodeEAN8(payload), humanReadable: payload)
        case .itf14:
            return LinearBarcode(modules: try encodeITF(payload), humanReadable: payload)
        case .code39:
            return LinearBarcode(modules: try encodeCode39(payload), humanReadable: payload)
        case .qr, .aztec, .pdf417, .code128:
            throw BarcodeError.unsupportedEncoding(symbology.displayName)
        }
    }

    // MARK: - EAN / UPC

    static let leftOddPatterns = [
        "0001101", "0011001", "0010011", "0111101", "0100011",
        "0110001", "0101111", "0111011", "0110111", "0001011",
    ]

    static let leftEvenPatterns = [
        "0100111", "0110011", "0011011", "0100001", "0011101",
        "0111001", "0000101", "0010001", "0001001", "0010111",
    ]

    static let rightPatterns = [
        "1110010", "1100110", "1101100", "1000010", "1011100",
        "1001110", "1010000", "1000100", "1001000", "1110100",
    ]

    /// Which of the first six digits use even parity, selected by the leading digit.
    static let parityPatterns = [
        "OOOOOO", "OOEOEE", "OOEEOE", "OOEEEO", "OEOOEE",
        "OEEOOE", "OEEEOO", "OEOEOE", "OEOEEO", "OEEOEO",
    ]

    private static let normalGuard = "101"
    private static let centerGuard = "01010"

    private static func encodeEAN13(_ payload: String) throws -> [Bool] {
        let digits = try digitValues(payload, expectedCount: 13)
        let parity = Array(parityPatterns[digits[0]])

        var bits = normalGuard
        for index in 1...6 {
            let digit = digits[index]
            bits += parity[index - 1] == "O" ? leftOddPatterns[digit] : leftEvenPatterns[digit]
        }
        bits += centerGuard
        for index in 7...12 {
            bits += rightPatterns[digits[index]]
        }
        bits += normalGuard
        return modules(from: bits)
    }

    private static func encodeEAN8(_ payload: String) throws -> [Bool] {
        let digits = try digitValues(payload, expectedCount: 8)

        var bits = normalGuard
        for index in 0...3 {
            bits += leftOddPatterns[digits[index]]
        }
        bits += centerGuard
        for index in 4...7 {
            bits += rightPatterns[digits[index]]
        }
        bits += normalGuard
        return modules(from: bits)
    }

    // MARK: - Interleaved 2 of 5 (ITF-14)

    /// Element widths per digit: 1 is narrow, 2 is wide.
    static let itfPatterns: [[Int]] = [
        [1, 1, 2, 2, 1], [2, 1, 1, 1, 2], [1, 2, 1, 1, 2], [2, 2, 1, 1, 1], [1, 1, 2, 1, 2],
        [2, 1, 2, 1, 1], [1, 2, 2, 1, 1], [1, 1, 1, 2, 2], [2, 1, 1, 2, 1], [1, 2, 1, 2, 1],
    ]

    private static func encodeITF(_ payload: String) throws -> [Bool] {
        let digits = try digitValues(payload, expectedCount: payload.count)
        guard digits.count.isMultiple(of: 2) else { throw BarcodeError.oddDigitCount }

        // Start: narrow bar, narrow space, narrow bar, narrow space.
        var modules: [Bool] = [true, false, true, false]

        for pairIndex in stride(from: 0, to: digits.count, by: 2) {
            let bars = itfPatterns[digits[pairIndex]]
            let spaces = itfPatterns[digits[pairIndex + 1]]
            for element in 0..<5 {
                modules.append(contentsOf: Array(repeating: true, count: bars[element]))
                modules.append(contentsOf: Array(repeating: false, count: spaces[element]))
            }
        }

        // Stop: wide bar, narrow space, narrow bar.
        modules.append(contentsOf: [true, true, false, true])
        return modules
    }

    // MARK: - Code 39

    /// Twelve module patterns (2:1 ratio) for every character in `code39Alphabet`, plus `*`.
    static let code39Patterns: [Character: String] = [
        "0": "101001101101", "1": "110100101011", "2": "101100101011", "3": "110110010101",
        "4": "101001101011", "5": "110100110101", "6": "101100110101", "7": "101001011011",
        "8": "110100101101", "9": "101100101101", "A": "110101001011", "B": "101101001011",
        "C": "110110100101", "D": "101011001011", "E": "110101100101", "F": "101101100101",
        "G": "101010011011", "H": "110101001101", "I": "101101001101", "J": "101011001101",
        "K": "110101010011", "L": "101101010011", "M": "110110101001", "N": "101011010011",
        "O": "110101101001", "P": "101101101001", "Q": "101010110011", "R": "110101011001",
        "S": "101101011001", "T": "101011011001", "U": "110010101011", "V": "100110101011",
        "W": "110011010101", "X": "100101101011", "Y": "110010110101", "Z": "100110110101",
        "-": "100101011011", ".": "110010101101", " ": "100110101101", "$": "100100100101",
        "/": "100100101001", "+": "100101001001", "%": "101001001001", "*": "100101101101",
    ]

    private static func encodeCode39(_ payload: String) throws -> [Bool] {
        let characters = Array("*" + payload.uppercased() + "*")
        var bits = ""
        for (index, character) in characters.enumerated() {
            guard let pattern = code39Patterns[character] else {
                throw BarcodeError.unsupportedCharacter(character)
            }
            bits += pattern
            // One narrow space separates characters, but not after the closing guard.
            if index < characters.count - 1 { bits += "0" }
        }
        return modules(from: bits)
    }

    // MARK: - Helpers

    private static func digitValues(_ payload: String, expectedCount: Int) throws -> [Int] {
        let values = payload.compactMap { $0.wholeNumberValue }
        guard values.count == payload.count else { throw BarcodeError.nonNumericPayload }
        guard values.count == expectedCount else {
            throw BarcodeError.unsupportedDigitCount(accepted: [expectedCount])
        }
        return values
    }

    private static func modules(from bits: String) -> [Bool] {
        bits.map { $0 == "1" }
    }
}
