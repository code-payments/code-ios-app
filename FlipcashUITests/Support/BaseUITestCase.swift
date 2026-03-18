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

    /// Asserts that the main screen (ScanScreen) has been reached by checking for the Give button.
    func assertMainScreenReached(timeout: TimeInterval = 30, _ message: String = "Expected to reach the main screen") {
        XCTAssertTrue(
            app.buttons["Give"].waitForExistence(timeout: timeout),
            message
        )
    }
}
