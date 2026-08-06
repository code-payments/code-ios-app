//
//  BlockedUsersUIScreen.swift
//  FlipcashUITests
//

import XCTest

/// Page object for `BlockedUsersScreen` — the Settings › My Account › Blocked
/// list.
@MainActor
struct BlockedUsersUIScreen {

    private let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    // MARK: - Elements

    /// The screen's inline navigation title.
    var navigationBar: XCUIElement { app.navigationBars["Blocked"] }

    /// The empty-state heading, shown once the blocklist loads with no entries.
    var emptyStateHeading: XCUIElement { app.staticTexts["No One Blocked"] }

    /// The list of blocked users, present only when at least one user is blocked.
    var list: XCUIElement { app.scrollViews.firstMatch }

    // MARK: - Assertions

    /// Asserts the screen was reached and its `refresh()` settled into a
    /// terminal state — either the empty-state copy or a populated list — rather
    /// than hanging or crashing. Resilient to whatever the account's blocklist
    /// holds at run time (the standing account is never mutated by this test).
    func assertLoaded(timeout: TimeInterval = 20, from testCase: BaseUITestCase) {
        XCTAssertTrue(
            navigationBar.waitForExistence(timeout: timeout),
            "Expected the Blocked screen (navigation title 'Blocked')"
        )

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if emptyStateHeading.exists || list.exists { return }
            Thread.sleep(forTimeInterval: 0.25)
        }
        XCTFail(
            "Blocked screen never settled: expected the empty state or a populated list. On screen: [\(testCase.visibleText())]"
        )
    }
}
