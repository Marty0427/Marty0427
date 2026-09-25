import SwiftUI

@main
struct PocketPassApp: App {
    /// Launch argument that fills the wallet with sample cards held in memory.
    ///
    /// Screenshots need a wallet that looks lived-in and looks the same every run, and an
    /// empty first-launch screen shows nothing. The seeded store never touches the real file,
    /// so a test run cannot disturb anyone's cards.
    static let seededWalletArgument = "-uiTestSeededWallet"

    @StateObject private var store = PocketPassApp.makeStore()
    @StateObject private var settings = AppSettings()
    @StateObject private var lock = AppLockController()

    private static func makeStore() -> CardStore {
        guard ProcessInfo.processInfo.arguments.contains(seededWalletArgument) else {
            return CardStore()
        }
        return CardStore(repository: InMemoryCardRepository(cards: WalletCard.samples))
    }

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(settings)
                .environmentObject(lock)
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Re-lock as soon as the app leaves the foreground, so the wallet is not
            // sitting open in the app switcher.
            if newPhase != .active, settings.requiresUnlock {
                lock.lock()
            }
        }
    }
}
