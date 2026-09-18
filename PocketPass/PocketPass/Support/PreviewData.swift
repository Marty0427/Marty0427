import Foundation

extension WalletCard {
    /// Cards used by SwiftUI previews and tests. Every payload here is fictional.
    /// Not wrapped in `#if DEBUG`: `#Preview` bodies are compiled in release builds too.
    static let samples: [WalletCard] = [
        WalletCard(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            name: "Clubcard",
            organization: "Tesco",
            payload: "5901234123457",
            symbology: .ean13,
            category: .loyalty,
            theme: .ocean,
            notes: "",
            isFavorite: true
        ),
        WalletCard(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            name: "Prague → Lisbon",
            organization: "Boarding pass · 12A",
            payload: "M1DOE/JOHN       EABC123 PRGLISTP 0417 259Y012A0050 100",
            symbology: .aztec,
            category: .boardingPass,
            theme: .slate,
            notes: "Gate B7, boards 09:20",
            expirationDate: Calendar.current.date(byAdding: .day, value: 3, to: Date())
        ),
        WalletCard(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            name: "Climbing Gym",
            organization: "Boulder Club",
            payload: "MEMBER-48213",
            symbology: .code128,
            category: .membership,
            theme: .forest
        ),
        WalletCard(
            id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            name: "Festival Ticket",
            organization: "Riverside Open Air",
            payload: "https://tickets.example.com/t/9f2c41a8",
            symbology: .qr,
            category: .eventTicket,
            theme: .berry,
            expirationDate: Calendar.current.date(byAdding: .day, value: 30, to: Date())
        ),
    ]
}
