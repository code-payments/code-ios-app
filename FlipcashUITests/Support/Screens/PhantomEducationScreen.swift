//
//  PhantomEducationScreen.swift
//  FlipcashUITests
//

import XCTest

/// Page object for the PhantomEducationScreen — the pre-flight shown when
/// the user picks Phantom from `PurchaseMethodSheet` without a saved Phantom
/// session. Tapping `connectButton` triggers `walletConnection.connect()`
/// which deeplinks out to Phantom (tests can't reasonably continue past that
/// point on the local simulator without a real Phantom install).
@MainActor
struct PhantomEducationScreen {

    private let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    // MARK: - Elements

    var connectButton: XCUIElement {
        app.buttons["Connect Your Phantom Wallet"]
    }

    var title: XCUIElement {
        app.staticTexts["Buy With Phantom"]
    }

    // MARK: - Assertions

    func assertReached(timeout: TimeInterval = 10) {
        XCTAssertTrue(
            connectButton.waitForExistence(timeout: timeout),
            "Expected PhantomEducationScreen with 'Connect Your Phantom Wallet' CTA"
        )
    }
}
