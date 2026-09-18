import UIKit

/// Thin wrapper so every call site can respect the "Haptics" setting without repeating itself.
@MainActor
enum Haptics {
    static func success(enabled: Bool = true) {
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning(enabled: Bool = true) {
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    static func selection(enabled: Bool = true) {
        guard enabled else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
