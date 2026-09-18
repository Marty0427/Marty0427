import Foundation

/// Cleans up whatever was scanned or typed and turns it into the canonical payload for a
/// symbology, adding the check digit when the printed number omits it.
///
/// Everything here is pure, synchronous and platform independent so it can be unit tested
/// without a camera or a screen.
enum BarcodeValidator {

    /// Characters Code 39 can encode, in the order of its encoding table.
    static let code39Alphabet = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ-. $/+%"

    /// Returns the payload ready for encoding, or throws a message fit for display.
    static func normalize(_ raw: String, for symbology: BarcodeSymbology) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw BarcodeError.emptyPayload }

        if symbology.isNumericOnly {
            return try normalizeNumeric(trimmed, for: symbology)
        }

        guard trimmed.count <= symbology.maximumPayloadLength else {
            throw BarcodeError.payloadTooLong(limit: symbology.maximumPayloadLength)
        }

        switch symbology {
        case .code39:
            let uppercased = trimmed.uppercased()
            if let offender = uppercased.first(where: { !code39Alphabet.contains($0) }) {
                throw BarcodeError.unsupportedCharacter(offender)
            }
            return uppercased
        case .code128:
            guard trimmed.data(using: .ascii) != nil else {
                throw BarcodeError.unsupportedEncoding(symbology.displayName)
            }
            return trimmed
        default:
            return trimmed
        }
    }

    /// `true` when the payload is already usable for this symbology.
    static func isValid(_ raw: String, for symbology: BarcodeSymbology) -> Bool {
        (try? normalize(raw, for: symbology)) != nil
    }

    // MARK: - Numeric formats

    private static func normalizeNumeric(_ trimmed: String, for symbology: BarcodeSymbology) throws -> String {
        // Printed numbers are routinely spaced or hyphenated; those separators carry no data.
        let digits = trimmed.filter { !" -\u{2013}\u{2014}".contains($0) }
        guard digits.allSatisfy(\.isASCIIDigit) else { throw BarcodeError.nonNumericPayload }
        guard !digits.isEmpty else { throw BarcodeError.emptyPayload }

        switch symbology {
        case .ean13:
            return try completeGTIN(digits, fullLength: 13, symbology: symbology)
        case .ean8:
            return try completeGTIN(digits, fullLength: 8, symbology: symbology)
        case .upcA:
            return try completeGTIN(digits, fullLength: 12, symbology: symbology)
        case .itf14:
            return try completeGTIN(digits, fullLength: 14, symbology: symbology)
        case .upcE:
            return try normalizeUPCE(digits)
        default:
            return digits
        }
    }

    /// Appends the check digit when it is missing and verifies it when it is present.
    private static func completeGTIN(
        _ digits: String,
        fullLength: Int,
        symbology: BarcodeSymbology
    ) throws -> String {
        switch digits.count {
        case fullLength - 1:
            return digits + String(checkDigit(forBody: digits))
        case fullLength:
            let body = String(digits.dropLast())
            let expected = checkDigit(forBody: body)
            guard digits.last == expected else { throw BarcodeError.invalidCheckDigit(expected: expected) }
            return digits
        default:
            throw BarcodeError.unsupportedDigitCount(accepted: symbology.acceptedDigitCounts)
        }
    }

    private static func normalizeUPCE(_ digits: String) throws -> String {
        switch digits.count {
        case 6:
            // No number system given; "0" is the only one that round-trips for most retail codes.
            let body = "0" + digits
            return body + String(checkDigit(forBody: try expandUPCEBody(body)))
        case 7:
            guard let first = digits.first, first == "0" || first == "1" else {
                throw BarcodeError.unsupportedDigitCount(accepted: BarcodeSymbology.upcE.acceptedDigitCounts)
            }
            return digits + String(checkDigit(forBody: try expandUPCEBody(digits)))
        case 8:
            let body = String(digits.prefix(7))
            guard let first = body.first, first == "0" || first == "1" else {
                throw BarcodeError.unsupportedDigitCount(accepted: BarcodeSymbology.upcE.acceptedDigitCounts)
            }
            let expected = checkDigit(forBody: try expandUPCEBody(body))
            guard digits.last == expected else { throw BarcodeError.invalidCheckDigit(expected: expected) }
            return digits
        default:
            throw BarcodeError.unsupportedDigitCount(accepted: BarcodeSymbology.upcE.acceptedDigitCounts)
        }
    }

    /// Expands the 7 digit UPC-E body (number system + 6 digits) into the 11 digit UPC-A body.
    private static func expandUPCEBody(_ body: String) throws -> String {
        let characters = Array(body)
        guard characters.count == 7 else {
            throw BarcodeError.unsupportedDigitCount(accepted: BarcodeSymbology.upcE.acceptedDigitCounts)
        }
        let system = characters[0]
        let x = Array(characters[1...6])

        switch x[5] {
        case "0", "1", "2":
            return "\(system)\(x[0])\(x[1])\(x[5])0000\(x[2])\(x[3])\(x[4])"
        case "3":
            return "\(system)\(x[0])\(x[1])\(x[2])00000\(x[3])\(x[4])"
        case "4":
            return "\(system)\(x[0])\(x[1])\(x[2])\(x[3])00000\(x[4])"
        default:
            return "\(system)\(x[0])\(x[1])\(x[2])\(x[3])\(x[4])0000\(x[5])"
        }
    }

    /// Full 12 digit UPC-A equivalent of a UPC-E payload, which is what a till actually records.
    static func upcAEquivalent(ofUPCE payload: String) throws -> String {
        let normalized = try normalizeUPCE(payload)
        let expanded = try expandUPCEBody(String(normalized.prefix(7)))
        return expanded + String(checkDigit(forBody: expanded))
    }

    // MARK: - Check digits

    /// The GS1 modulo-10 check digit shared by EAN-8, EAN-13, UPC-A and ITF-14.
    /// Weights alternate 3 and 1 starting from the rightmost body digit.
    static func checkDigit(forBody body: String) -> Character {
        var sum = 0
        for (offset, character) in body.reversed().enumerated() {
            guard let value = character.wholeNumberValue else { continue }
            sum += offset.isMultiple(of: 2) ? value * 3 : value
        }
        return Character(String((10 - sum % 10) % 10))
    }
}

extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
