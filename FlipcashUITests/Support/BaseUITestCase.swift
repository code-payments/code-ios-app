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

    /// Beta-flag option rawValues to enable for the test via `--beta-flags`.
    var enabledBetaFlags: [String] { [] }

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false

        app.launchArguments = ["--ui-testing", "-AppleLocale", "en_US", "-AppleLanguages", "(en)"]

        if !enabledBetaFlags.isEmpty {
            app.launchArguments.append("--beta-flags=\(enabledBetaFlags.joined(separator: ","))")
        }

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
            try loginTestAccount()
        } else if requiresUsdfOnlyAccount {
            let accessKey = Bundle(for: Self.self).infoDictionary?["UITestUsdfOnlyAccessKey"] as? String ?? ""
            try XCTSkipIf(accessKey.isEmpty, "FLIPCASH_UI_TEST_USDF_ONLY_ACCESS_KEY not set in secrets.local.xcconfig — skipping USDF-only UI test")

            let loginURL = URL(string: "flipcash://login#e=\(accessKey.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? accessKey)")!
            app.open(loginURL)
        }
    }

    // MARK: - Helpers

    /// Logs into the funded test account via the login deeplink, skipping the
    /// test when no access key is configured. Callable mid-test after a
    /// relaunch as well as from `setUp`.
    func loginTestAccount() throws {
        let accessKey = Bundle(for: Self.self).infoDictionary?["UITestAccessKey"] as? String ?? ""
        try XCTSkipIf(accessKey.isEmpty, "FLIPCASH_UI_TEST_ACCESS_KEY not set in secrets.local.xcconfig — skipping authenticated UI test")

        let loginURL = URL(string: "flipcash://login#e=\(accessKey.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? accessKey)")!
        app.open(loginURL)
    }

    /// Registers a new account via the write-down branch — the fastest path,
    /// and the only one that needs no Photos permission.
    func createFreshAccount() {
        waitAndTap(app.buttons["Create a New Account"])
        waitAndTap(app.buttons["Wrote the 12 Words Down Instead?"])
        waitAndTap(app.buttons["Yes, I Wrote Them Down"])
        allowPhoneVerificationIfNeeded()
        allowPushNotificationsIfNeeded()
        assertMainScreenReached()
    }

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

    /// Drives the phone-verification flow using the backend mock phone
    /// (`+15005550000`), which auto-succeeds `SendVerificationCode` and
    /// `CheckVerificationCode` regardless of the typed code. Resilient to
    /// the case where the flow isn't presented (re-auth, prior verify).
    /// Detection uses per-screen elements rather than the navigation title
    /// because both EnterPhoneScreen and ConfirmPhoneScreen render under
    /// the same nav title.
    func allowPhoneVerificationIfNeeded() {
        // EnterPhoneScreen signature: the "Phone Number" text field.
        let phoneField = app.textFields["Phone Number"]
        guard phoneField.waitForExistence(timeout: 2) else { return }
        phoneField.tap()
        // Enter the mock number in full international form, including the "+1"
        // country code. A valid number auto-advances to the code screen, so no
        // "Next" tap is needed.
        phoneField.typeText("+15005550000")

        // ConfirmPhoneScreen signature: the Confirm CodeButton. The hidden
        // code field auto-focuses ~100ms after appear; six typed digits
        // trigger `confirmPhoneNumberCodeAction()` via the onChange hook.
        let confirmButton = app.buttons["Confirm"]
        XCTAssertTrue(
            confirmButton.waitForExistence(timeout: 10),
            "Expected `ConfirmPhoneScreen` after submitting the mock phone number"
        )
        app.typeText("123456")

        // Success signal: the Confirm button has gone away.
        let dismissed = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: dismissed, object: confirmButton)
        let result = XCTWaiter().wait(for: [expectation], timeout: 15)
        XCTAssertEqual(
            result, .completed,
            "Phone verification did not advance past `ConfirmPhoneScreen` within 15s"
        )
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

    /// Picks the newest photo from the system library and commits the crop
    /// editor. Returns false when the library is empty, which is the state of a
    /// freshly created simulator.
    func selectFirstPhotoFromLibrary(via picker: XCUIElement) -> Bool {
        picker.tap()

        // The Menu offers Photo Library / Choose File.
        waitAndTap(app.buttons["Photo Library"])

        // The library is a remote view hosted inside the app's own hierarchy, so
        // it is reachable from `app` rather than a separate process. Its
        // thumbnails are images tagged `PXGGridLayout-Info` — they are not
        // collection-view cells, and querying `cells` finds nothing. The head of
        // the grid is always on screen; thumbnails further down are in the tree
        // but below the fold, so a coordinate tap on them lands nowhere.
        let thumbnail = app.images.matching(identifier: "PXGGridLayout-Info").firstMatch
        guard thumbnail.waitForExistence(timeout: 30) else { return false }

        if thumbnail.isHittable {
            thumbnail.tap()
        } else {
            thumbnail.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }

        // `allowsEditing` puts a crop editor in front of the selection; "Choose"
        // is what actually returns the image.
        let choose = app.buttons["Choose"]
        guard choose.waitForExistence(timeout: 20) else { return false }
        choose.tap()

        return true
    }

    /// Everything legible on screen, for failure messages.
    func visibleText() -> String {
        app.staticTexts.allElementsBoundByIndex
            .prefix(15)
            .map(\.label)
            .filter { !$0.isEmpty }
            .joined(separator: " | ")
    }

    /// Handles the contacts permission flow if it appears. Resilient to:
    ///   - the determined-status case where the gate screen is skipped entirely
    ///   - the springboard "Continue" alert, which any iOS version may show
    ///     and which renders slowly on a loaded host
    ///   - the share picker, hosted in a dedicated XPC process on iOS 18+
    ///     (`com.apple.ContactsUI.LimitedAccessPromptView`) or by springboard
    /// One loop drives whichever system step is on screen and fails the test
    /// if the flow never completes — a swallowed miss leaves the alert
    /// covering the app and wedges every test that follows in the bundle.
    func allowContactsIfNeeded() {
        // The in-app priming button, targeted by identifier: a bare "Continue" label is ambiguous
        // (the scan screen's camera prompt behind the sheet carries the same label), and scoping to
        // `app` alone never matches the system alert's own "Continue" (`springboard`, tapped below).
        let appContinueButton = app.buttons["contacts-continue-button"]
        guard appContinueButton.waitForExistence(timeout: 5) else { return }
        appContinueButton.tap()

        let springboard   = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let limitedAccess = XCUIApplication(bundleIdentifier: "com.apple.ContactsUI.LimitedAccessPromptView")

        // Naming the bundle scopes each query without taking focus from the
        // picker (`.activate()` would launch the process fresh and steal
        // foreground). Queries against a non-running process return empty
        // hierarchies, so polling both hosts is safe.
        let sharePredicate = NSPredicate(format: "label BEGINSWITH[c] 'Share All'")
        let deadline = Date().addingTimeInterval(60)
        while Date() < deadline {
            for host in [limitedAccess, springboard] {
                let shareAll = host.buttons.matching(sharePredicate).firstMatch
                if shareAll.exists, shareAll.isHittable {
                    shareAll.tap()
                    return
                }
            }

            let continueButton = springboard.buttons["Continue"]
            if continueButton.exists, continueButton.isHittable {
                continueButton.tap()
            }

            Thread.sleep(forTimeInterval: 0.25)
        }

        XCTFail("Contacts permission flow did not complete within 60s — the system alert or share picker never became tappable")
    }

}
