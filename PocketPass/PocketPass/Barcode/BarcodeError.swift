import Foundation

/// Why a payload could not be turned into a scannable symbol. Surfaced verbatim in the editor,
/// so every case carries a message a non-technical person can act on.
enum BarcodeError: LocalizedError, Equatable {
    case emptyPayload
    case payloadTooLong(limit: Int)
    case nonNumericPayload
    case unsupportedDigitCount(accepted: [Int])
    case oddDigitCount
    case invalidCheckDigit(expected: Character)
    case unsupportedCharacter(Character)
    case unsupportedEncoding(String)
    case renderingFailed

    var errorDescription: String? {
        switch self {
        case .emptyPayload:
            return "Enter the code printed on the card."
        case .payloadTooLong(let limit):
            return "This format holds at most \(limit) characters."
        case .nonNumericPayload:
            return "This format only accepts digits."
        case .unsupportedDigitCount(let accepted):
            let list = accepted.map(String.init).joined(separator: " or ")
            return "This format needs \(list) digits."
        case .oddDigitCount:
            return "This format needs an even number of digits."
        case .invalidCheckDigit(let expected):
            return "The last digit should be \(expected). Check the number and try again."
        case .unsupportedCharacter(let character):
            return "“\(character)” can’t be encoded in this format."
        case .unsupportedEncoding(let name):
            return "\(name) needs plain ASCII characters."
        case .renderingFailed:
            return "The code couldn’t be drawn. Try a different format."
        }
    }
}
