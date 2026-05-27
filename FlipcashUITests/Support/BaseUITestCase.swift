//
//  BaseUITestCase.swift
//  FlipcashUITests
//

import XCTest

@MainActor
class BaseUITestCase: XCTestCase {

    let app = XCUIApplication()

    /// Whether this test case requires the user to be logged in.
    /// Override in subclasses that need authentication.
    var requiresAuthentication: Bool { false }

    /// Whether this test case requires login as the USDF-only-funded account.
    /// Override in subclasses that need to assert behavior specific to a
    /// wallet holding only USDF (no other currencies). Mutually exclusive
    /// with `requiresAuthentication`.
    var requiresUsdfOnlyAccount: Bool { false }

    /// Override to reset specific permissions before each test.
    /// Example: `[.photos, .camera]`
    var resetPermissions: [XCUIProtectedResource] { [] }

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false

        app.launchArguments = ["--ui-testing", "-AppleLocale", "en_US", "-AppleLanguages", "(en)"]

        for permission in resetPermissions {
            app.resetAuthorizationStatus(for: permission)
        }

        // Always launch with `app.launch()` first so the configured
        // `launchArguments` (including `--ui-testing`) are applied and
        // `SessionAuthenticator.nukeForUITesting()` fires. `app.open(URL)`
        // alone uses URL-scheme dispatch and does NOT pass launchArguments,
        // which would leave the keychain in whatever state the previous run
        // left behind and let the auto-login path fire `createAccounts`.
        app.launch()

        if requiresAuthentication {
            let accessKey = Bundle(for: Self.self).infoDictionary?["UITestAccessKey"] as? String ?? ""
            try XCTSkipIf(accessKey.isEmpty, "FLIPCASH_UI_TEST_ACCESS_KEY not set in secrets.local.xcconfig — skipping authenticated UI test")

            let loginURL = URL(string: "flipcash://login#e=\(accessKey.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? accessKey)")!
            app.open(loginURL)
        } else if requiresUsdfOnlyAccount {
            let accessKey = Bundle(for: Self.self).infoDictionary?["UITestUsdfOnlyAccessKey"] as? String ?? ""
            try XCTSkipIf(accessKey.isEmpty, "FLIPCASH_UI_TEST_USDF_ONLY_ACCESS_KEY not set in secrets.local.xcconfig — skipping USDF-only UI test")

            let loginURL = URL(string: "flipcash://login#e=\(accessKey.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? accessKey)")!
            app.open(loginURL)
        }
    }

    // MARK: - Helpers

    /// Waits for an element to appear and taps it. Fails the test if the element doesn't appear within the timeout.
    func waitAndTap(_ element: XCUIElement, timeout: TimeInterval = 30, _ message: String? = nil) {
        let defaultMessage = "Expected \(element) to exist within \(timeout)s"
        XCTAssertTrue(element.waitForExistence(timeout: timeout), message ?? defaultMessage)
        element.tap()
    }

    /// Waits for an element to be hittable (on-screen, not obscured, done animating) and taps it.
    /// Use this for elements that may still be animating into position (e.g. system permission dialogs).
    func waitUntilHittableAndTap(_ element: XCUIElement, timeout: TimeInterval = 30, _ message: String? = nil) {
        let predicate = NSPredicate(format: "isHittable == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)
        let defaultMessage = "Expected \(element) to be hittable within \(timeout)s"
        XCTAssertEqual(result, .completed, message ?? defaultMessage)
        element.tap()
    }

    /// Asserts that the main screen (ScanScreen) has been reached by checking for the Cash button.
    func assertMainScreenReached(timeout: TimeInterval = 30, _ message: String = "Expected to reach the main screen") {
        XCTAssertTrue(
            app.buttons["Cash"].waitForExistence(timeout: timeout),
            message
        )
    }

    /// Navigates into the Give flow, retrying up to 3 times if the balance hasn't loaded yet.
    /// On CI the balance may not be fetched immediately, showing a "No Balance Yet" dialog.
    /// Returns an `AmountEntryScreen` ready for amount entry.
    @discardableResult
    func navigateToGiveAmount() -> AmountEntryScreen {
        let amountEntry = AmountEntryScreen(app: app)

        for attempt in 1...3 {
            waitAndTap(app.buttons["Cash"])
            if amountEntry.keypadZero.waitForExistence(timeout: 10) { break }

            let ok = app.buttons["OK"]
            if ok.exists { ok.tap() }

            if attempt == 3 {
                XCTFail("Balance did not load after 3 attempts")
            }
        }

        return amountEntry
    }

    /// Handles the push notification permission screen if it appears.
    /// The screen is skipped when notification permissions are already determined,
    /// so this helper is resilient to both states.
    func allowPushNotificationsIfNeeded() {
        let okButton = app.buttons["OK"]
        guard okButton.waitForExistence(timeout: 2) else { return }
        okButton.tap()

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        waitUntilHittableAndTap(springboard.buttons["Allow"])
    }

    /// Handles the contacts permission screen if it appears. Resilient to:
    ///   - the determined-status case where the screen is skipped entirely
    ///   - iOS 18 jumping straight to the share picker (no Continue prompt)
    ///   - iOS 26+ showing a Continue prompt before the share picker
    /// iOS 18+ hosts the share picker in a dedicated XPC process,
    /// `com.apple.ContactsUI.LimitedAccessPromptView`. The process must be
    /// activated explicitly — queries against the non-frontmost process
    /// return empty hierarchies even when the picker is on screen. Older
    /// iOS variants present the same picker from springboard, so springboard
    /// is the fallback.
    func allowContactsIfNeeded() {
        let giveAccessButton = app.buttons["Give Access To Contacts"]
        guard giveAccessButton.waitForExistence(timeout: 2) else { return }
        giveAccessButton.tap()

        let springboard   = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let limitedAccess = XCUIApplication(bundleIdentifier: "com.apple.ContactsUI.LimitedAccessPromptView")

        // iOS 26+ Continue prompt — absent on earlier iOS.
        let continueButton = springboard.buttons["Continue"]
        if continueButton.waitForExistence(timeout: 2) {
            waitUntilHittableAndTap(continueButton)
        }

        // Share picker. iOS 18+ hosts this in a dedicated XPC process
        // (com.apple.ContactsUI.LimitedAccessPromptView); some iOS variants
        // host it from springboard. Poll both — naming the bundle scopes
        // the query without taking focus from the picker (`.activate()`
        // would launch the process fresh and steal foreground).
        let predicate    = NSPredicate(format: "label BEGINSWITH[c] 'Share All'")
        let candidates: [XCUIApplication] = [limitedAccess, springboard]
        let deadline     = Date().addingTimeInterval(10)
        while Date() < deadline {
            for candidate in candidates {
                let button = candidate.buttons.matching(predicate).firstMatch
                if button.exists {
                    waitUntilHittableAndTap(button)
                    return
                }
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
    }

}
