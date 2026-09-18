import LocalAuthentication
import SwiftUI

/// Optional Face ID / Touch ID / passcode gate in front of the wallet.
///
/// The lock is a privacy screen, not encryption: cards are protected on disk by iOS file
/// protection either way. That distinction is stated plainly in Settings too.
@MainActor
final class AppLockController: ObservableObject {

    @Published private(set) var isUnlocked = false
    @Published private(set) var failureMessage: String?
    @Published private(set) var isAuthenticating = false

    private let contextProvider: () -> LAContext

    init(contextProvider: @escaping () -> LAContext = { LAContext() }) {
        self.contextProvider = contextProvider
    }

    /// Name of the biometry the device offers, for the Settings toggle label.
    var biometryDisplayName: String {
        let context = contextProvider()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Passcode"
        }
    }

    /// `true` when the device can authenticate the owner at all.
    var isAvailable: Bool {
        contextProvider().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    func lock() {
        isUnlocked = false
        failureMessage = nil
    }

    func unlockWithoutAuthenticating() {
        isUnlocked = true
        failureMessage = nil
    }

    func authenticate(reason: String = "Unlock your cards") async {
        guard !isAuthenticating else { return }

        let context = contextProvider()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // No passcode set: locking would trap the owner out of their own cards.
            isUnlocked = true
            failureMessage = nil
            return
        }

        isAuthenticating = true
        defer { isAuthenticating = false }

        do {
            let success = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            isUnlocked = success
            failureMessage = success ? nil : "Authentication failed."
        } catch {
            isUnlocked = false
            failureMessage = (error as? LAError).map(Self.message(for:)) ?? error.localizedDescription
        }
    }

    private static func message(for error: LAError) -> String {
        switch error.code {
        case .userCancel, .appCancel, .systemCancel:
            return "Unlock cancelled."
        case .userFallback:
            return "Enter your device passcode to continue."
        case .biometryLockout:
            return "Biometrics are locked. Use your device passcode."
        default:
            return error.localizedDescription
        }
    }
}
