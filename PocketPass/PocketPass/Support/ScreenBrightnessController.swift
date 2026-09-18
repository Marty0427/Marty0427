import UIKit

/// Turns the screen up while a code is on show and puts it back afterwards.
///
/// This is the difference between a card that scans first time and one that does not:
/// shop scanners struggle with a dim phone, especially behind a matte screen protector.
@MainActor
final class ScreenBrightnessController: ObservableObject {

    private var previousBrightness: CGFloat?
    private var previousIdleTimerDisabled: Bool?

    private var screen: UIScreen {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        return scene?.screen ?? UIScreen.main
    }

    /// - Parameters:
    ///   - level: target brightness, 0...1.
    ///   - keepAwake: also hold off auto-lock, so a pass does not dim while queuing.
    func boost(to level: CGFloat = 1.0, keepAwake: Bool = true) {
        if previousBrightness == nil {
            previousBrightness = screen.brightness
        }
        screen.brightness = min(max(level, 0), 1)

        if keepAwake, previousIdleTimerDisabled == nil {
            previousIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
            UIApplication.shared.isIdleTimerDisabled = true
        }
    }

    /// Restores whatever the owner had before. Safe to call when no boost is active.
    ///
    /// Views call this from `onDisappear`; there is deliberately no `deinit` fallback, as
    /// `deinit` cannot hop to the main actor to touch `UIScreen`.
    func restore() {
        if let previousBrightness {
            screen.brightness = previousBrightness
            self.previousBrightness = nil
        }
        if let previousIdleTimerDisabled {
            UIApplication.shared.isIdleTimerDisabled = previousIdleTimerDisabled
            self.previousIdleTimerDisabled = nil
        }
    }
}
