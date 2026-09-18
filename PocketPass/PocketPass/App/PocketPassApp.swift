import SwiftUI

@main
struct PocketPassApp: App {
    @StateObject private var store = CardStore()
    @StateObject private var settings = AppSettings()
    @StateObject private var lock = AppLockController()

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
