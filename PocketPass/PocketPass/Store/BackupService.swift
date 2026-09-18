import Foundation

/// Plain-JSON export and import.
///
/// The backup is deliberately readable: passes are the owner's data, and a format they can
/// open in any text editor is what keeps the wallet from being a trap.
enum BackupService {

    static let currentVersion = 1
    /// Plain `.json`, so the file opens anywhere and needs no custom document type.
    static let fileExtension = "json"

    struct Backup: Codable {
        var version: Int
        var exportedAt: Date
        var cards: [WalletCard]
    }

    /// Writes a backup into the temporary directory and returns its URL, ready to share.
    static func writeBackup(
        cards: [WalletCard],
        in directory: URL = FileManager.default.temporaryDirectory,
        date: Date = Date()
    ) throws -> URL {
        let backup = Backup(version: currentVersion, exportedAt: date, cards: cards)
        let data = try CardCoding.encoder.encode(backup)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let name = "PocketPass-\(formatter.string(from: date)).\(fileExtension)"

        let url = directory.appendingPathComponent(name, isDirectory: false)
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Reads a backup file. Accepts both the envelope and a bare array of cards, so a file
    /// trimmed down by hand still restores.
    static func readBackup(from data: Data) throws -> [WalletCard] {
        let decoder = CardCoding.decoder
        if let backup = try? decoder.decode(Backup.self, from: data) {
            return backup.cards
        }
        return try decoder.decode([WalletCard].self, from: data)
    }

    static func readBackup(at url: URL) throws -> [WalletCard] {
        // Files handed over by the document picker live outside the sandbox.
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }
        return try readBackup(from: try Data(contentsOf: url))
    }
}
