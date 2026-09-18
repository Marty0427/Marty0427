import Foundation

/// Storage behind the wallet. Abstracted so the store can be exercised in tests without a disk.
protocol CardRepository: AnyObject {
    func load() throws -> [WalletCard]
    func save(_ cards: [WalletCard]) throws
}

/// JSON file storage in Application Support.
///
/// Passes never leave the device: there is no account, no sync and no analytics, so a single
/// protected file is the whole persistence story.
final class FileCardRepository: CardRepository {
    private let fileURL: URL
    private let fileManager: FileManager

    init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = (try? fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )) ?? fileManager.temporaryDirectory
            self.fileURL = base
                .appendingPathComponent("PocketPass", isDirectory: true)
                .appendingPathComponent("cards.json", isDirectory: false)
        }
    }

    var storageURL: URL { fileURL }

    func load() throws -> [WalletCard] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else { return [] }
        return try CardCoding.decoder.decode([WalletCard].self, from: data)
    }

    func save(_ cards: [WalletCard]) throws {
        let directory = fileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let data = try CardCoding.encoder.encode(cards)
        // Complete protection: the file is unreadable while the device is locked, and the app
        // only ever touches it in the foreground.
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }
}

/// In-memory storage for previews and tests.
final class InMemoryCardRepository: CardRepository {
    private(set) var storedCards: [WalletCard]
    /// When set, the next `save` throws this error. Used to exercise failure handling.
    var saveError: Error?

    init(cards: [WalletCard] = []) {
        self.storedCards = cards
    }

    func load() throws -> [WalletCard] { storedCards }

    func save(_ cards: [WalletCard]) throws {
        if let saveError { throw saveError }
        storedCards = cards
    }
}

enum CardCoding {
    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
