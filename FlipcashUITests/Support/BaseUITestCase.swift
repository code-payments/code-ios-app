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
        enterDisplayNameIfNeeded()
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

    /// Waits for an element to exist, swipes `container` up until it is hittable,
    /// and taps it.
    ///
    /// Use for content that is in the hierarchy but below the fold — an
    /// off-screen element is never hittable, so `waitUntilHittableAndTap` just
    /// burns its whole timeout waiting for a scroll that nothing performs.
    func scrollUpToAndTap(
        _ element: XCUIElement,
        in container: XCUIElement,
        maxSwipes: Int = 8,
        _ message: String? = nil
    ) {
        XCTAssertTrue(
            element.waitForExistence(timeout: 30),
            message ?? "Expected \(element) to exist within 30s"
        )

        // `.slow` keeps the scroll from flinging: a fling is still decelerating
        // when the swipe call returns, so the element the query just found
        // hittable has moved by the time the tap lands.
        var swipes = 0
        while !element.isHittable, swipes < maxSwipes {
            container.swipeUp(velocity: .slow)
            swipes += 1
        }

        XCTAssertTrue(
            element.isHittable,
            message ?? "Expected \(element) to be hittable after \(maxSwipes) swipes"
        )

        waitForStableFrame(element)
        element.tap()
    }

    /// Blocks until `element`'s frame stops moving, so a tap can't land on
    /// whatever slid into its place. Content arriving asynchronously (balances,
    /// recent activity) reflows the page under a scroll that has already ended,
    /// which a settled scroll offset alone wouldn't catch.
    func waitForStableFrame(_ element: XCUIElement, timeout: TimeInterval = 5) {
        let deadline = Date().addingTimeInterval(timeout)
        var previous = element.frame
        while Date() < deadline {
            Thread.sleep(forTimeInterval: 0.2)
            let current = element.frame
            if current == previous { return }
            previous = current
        }
    }

    /// Asserts that the main screen has been reached by checking for the Wallet
    /// tab, the launch tab of the tab-bar UI.
    ///
    /// The tab bar hides itself once a screen is pushed onto the active tab's
    /// stack, so this only holds at a tab root — which is what "main screen"
    /// means at every call site.
    func assertMainScreenReached(timeout: TimeInterval = 30, _ message: String = "Expected to reach the main screen") {
        XCTAssertTrue(
            app.buttons["Wallet"].waitForExistence(timeout: timeout),
            message
        )
    }

    /// Skips a test whose entry point was the v1 scanner chrome, removed when
    /// the tab-bar UI shipped to everyone.
    ///
    /// These flows still exist but are reached differently now, so each call
    /// site needs a rewrite verified against a simulator rather than a selector
    /// swap. Grep this symbol for the outstanding list; it goes away with the
    /// last one.
    func skipPendingTabBarRewrite(_ detail: String) throws {
        throw XCTSkip("Pending rewrite for the tab-bar UI: \(detail)")
    }

    /// Navigates into the Give flow through a held currency's Give tile — the
    /// tab-bar UI's only entry, now that the scanner's Cash button went with the
    /// bottom bar. Returns an `AmountEntryScreen` ready for amount entry.
    ///
    /// Picks the first non-USDF card, so the flow runs on a community currency
    /// the way the Cash button's default did. No balance retry: the Give tile is
    /// only drawn for a currency the account holds, so there is no "No Balance
    /// Yet" gate on this path — an unloaded balance shows up as a missing card,
    /// which `selectFirstCurrency` already waits out.
    ///
    /// The keypad is pushed over the currency's info screen and pops itself as
    /// the bill appears, so the flow ends up back on `CurrencyInfoScreen` rather
    /// than on a tab root.
    @discardableResult
    func navigateToGiveAmount() -> AmountEntryScreen {
        let wallet = WalletScreen(app: app)
        let currencyInfo = CurrencyInfoUIScreen(app: app)
        let amountEntry = AmountEntryScreen(app: app)

        wallet.open(from: self)
        wallet.selectFirstCurrency()
        currencyInfo.assertHeldCurrencyReached(timeout: 30)
        waitAndTap(currencyInfo.giveButton)

        XCTAssertTrue(
            amountEntry.keypadZero.waitForExistence(timeout: 30),
            "Expected the give keypad after tapping the currency's Give tile"
        )

        return amountEntry
    }

    /// Enters a display name on the onboarding name step — the mandatory step
    /// that replaced phone verification. Resilient to the screen not appearing
    /// (e.g. recovering an account that already has a name).
    func enterDisplayNameIfNeeded() {
        // OnboardingNameScreen signature: the "Your Name" text field.
        let nameField = app.textFields["Your Name"]
        guard nameField.waitForExistence(timeout: 15) else { return }
        nameField.tap()
        nameField.typeText("Test User")
        waitAndTap(app.buttons["onboarding-name-next-button"])
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
    func allowPushNotificationsIfNeeded(timeout: TimeInterval = 30) {
        let okButton = app.buttons["OK"]
        let deadline = Date().addingTimeInterval(timeout)

        // Account registration gates the screen, so after a fresh sign-up it can
        // take well over ten seconds to appear. The tab bar is the only other
        // outcome, and checking for it each round ends the wait immediately when
        // the screen was skipped.
        while !okButton.waitForExistence(timeout: 1) {
            if app.buttons["Wallet"].exists { return }
            if Date() >= deadline { return }
        }

        okButton.tap()

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        waitUntilHittableAndTap(springboard.buttons["Allow"])
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
