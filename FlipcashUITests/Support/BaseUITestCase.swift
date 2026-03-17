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

            let loginURL = URL(string: "flipcash://login#e=\(accessKey)")!
            app.open(loginURL)
        } else {
            app.launch()
        }
    }
}
