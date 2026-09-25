import XCTest

/// Walks the app and photographs each screen.
///
/// This serves two purposes at once: it produces the App Store screenshots, and it is the
/// only check that the SwiftUI views actually render and navigate, which compiling and unit
/// testing cannot tell you.
///
/// Every screen is reached by tapping, never by typing: entering text in a simulator depends
/// on which keyboard is attached, and a screenshot run should not be able to fail on that.
final class ScreenshotTests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        // Carry on after a failed step: one screen that will not open should not cost us
        // the screenshots of every screen after it.
        continueAfterFailure = true

        app = XCUIApplication()
        app.launchArguments += [PocketPassLaunchArgument.seededWallet]
        app.launch()
    }

    func testCaptureEveryScreen() {
        XCTAssertTrue(
            app.navigationBars["Cards"].waitForExistence(timeout: 60),
            "The wallet never appeared after launch."
        )
        capture("01-wallet")

        guard openFirstCard() else { return }
        capture("02-card")

        captureEditor()
        goBack()
        captureSettings()
    }

    // MARK: - Screens

    private func openFirstCard() -> Bool {
        let tile = app.buttons.matching(identifier: "cardTile").firstMatch
        guard tile.waitForExistence(timeout: 15) else {
            XCTFail("No card tiles in the seeded wallet.")
            return false
        }
        tile.tap()

        // The barcode is rendered off the main thread, so wait for the screen's own controls.
        guard app.buttons["Copy Code"].waitForExistence(timeout: 15) else {
            XCTFail("The card detail screen did not open.")
            return false
        }
        return true
    }

    /// The editor is opened on an existing card, so the form is already filled in and the
    /// live barcode preview is on screen.
    private func captureEditor() {
        let more = app.buttons["More"]
        guard more.waitForExistence(timeout: 10) else {
            return XCTFail("The card's More menu is missing.")
        }
        more.tap()

        let edit = app.buttons["Edit"]
        guard edit.waitForExistence(timeout: 10) else {
            return XCTFail("The More menu did not open.")
        }
        edit.tap()

        guard app.navigationBars["Edit Card"].waitForExistence(timeout: 15) else {
            return XCTFail("The card editor did not open.")
        }
        capture("03-editor")

        app.buttons["Cancel"].firstMatch.tap()
    }

    private func captureSettings() {
        let settings = app.buttons["settingsButton"]
        guard settings.waitForExistence(timeout: 15) else {
            return XCTFail("The settings button is missing.")
        }
        settings.tap()

        guard app.navigationBars["Settings"].waitForExistence(timeout: 15) else {
            return XCTFail("Settings did not open.")
        }
        capture("04-settings")

        app.buttons["Done"].firstMatch.tap()
    }

    // MARK: - Helpers

    private func goBack() {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        if back.exists { back.tap() }
        _ = app.navigationBars["Cards"].waitForExistence(timeout: 10)
    }

    /// Attaches a full-screen capture to the test results, where CI extracts it.
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

/// The UI test bundle does not link the app, so the launch argument is spelled out here and
/// kept in step with `PocketPassApp.seededWalletArgument`.
enum PocketPassLaunchArgument {
    static let seededWallet = "-uiTestSeededWallet"
}
