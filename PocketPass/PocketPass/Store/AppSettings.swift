import Foundation

/// User preferences, persisted in `UserDefaults`.
@MainActor
final class AppSettings: ObservableObject {

    private enum Key {
        static let boostsBrightness = "settings.boostsBrightness"
        static let requiresUnlock = "settings.requiresUnlock"
        static let hapticsEnabled = "settings.hapticsEnabled"
        static let keepsScreenAwake = "settings.keepsScreenAwake"
    }

    private let defaults: UserDefaults

    /// Turn the screen up while a code is on screen; almost every scanner needs it.
    @Published var boostsBrightness: Bool {
        didSet { defaults.set(boostsBrightness, forKey: Key.boostsBrightness) }
    }

    /// Require Face ID, Touch ID or the passcode before the wallet is shown.
    @Published var requiresUnlock: Bool {
        didSet { defaults.set(requiresUnlock, forKey: Key.requiresUnlock) }
    }

    @Published var hapticsEnabled: Bool {
        didSet { defaults.set(hapticsEnabled, forKey: Key.hapticsEnabled) }
    }

    /// Hold off the auto-lock while a pass is open, so it does not dim mid-scan.
    @Published var keepsScreenAwake: Bool {
        didSet { defaults.set(keepsScreenAwake, forKey: Key.keepsScreenAwake) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.boostsBrightness: true,
            Key.requiresUnlock: false,
            Key.hapticsEnabled: true,
            Key.keepsScreenAwake: true,
        ])
        boostsBrightness = defaults.bool(forKey: Key.boostsBrightness)
        requiresUnlock = defaults.bool(forKey: Key.requiresUnlock)
        hapticsEnabled = defaults.bool(forKey: Key.hapticsEnabled)
        keepsScreenAwake = defaults.bool(forKey: Key.keepsScreenAwake)
    }
}
