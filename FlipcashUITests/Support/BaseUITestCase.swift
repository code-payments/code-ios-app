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

    /// Override to reset specific permissions before each test.
    /// Example: `[.photos, .camera]`
    var resetPermissions: [XCUIProtectedResource] { [] }

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false

        app.launchArguments = ["--ui-testing"]

        for permission in resetPermissions {
            app.resetAuthorizationStatus(for: permission)
        }

        if requiresAuthentication {
            let accessKey = Bundle(for: Self.self).infoDictionary?["UITestAccessKey"] as? String ?? ""
            try XCTSkipIf(accessKey.isEmpty, "FLIPCASH_UI_TEST_ACCESS_KEY not set in secrets.local.xcconfig — skipping authenticated UI test")

            let loginURL = URL(string: "flipcash://login#e=\(accessKey.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? accessKey)")!
            app.open(loginURL)
        } else {
            app.launch()
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

    /// Asserts that the main screen (ScanScreen) has been reached by checking for the Give button.
    func assertMainScreenReached(timeout: TimeInterval = 30, _ message: String = "Expected to reach the main screen") {
        XCTAssertTrue(
            app.buttons["Give"].waitForExistence(timeout: timeout),
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
            waitAndTap(app.buttons["Give"])
            if amountEntry.keypadZero.waitForExistence(timeout: 10) { break }

            let ok = app.buttons["OK"]
            if ok.exists { ok.tap() }

            if attempt == 3 {
                XCTFail("Balance did not load after 3 attempts")
            }
        }

        return amountEntry
    }

}
