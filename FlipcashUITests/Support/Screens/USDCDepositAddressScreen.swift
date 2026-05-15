//
//  USDCDepositAddressScreen.swift
//  FlipcashUITests
//

import XCTest

/// Page object for the USDCDepositAddressScreen — the leaf of the
/// "Other Wallet" buy path. Shows the per-user USDC deposit address and
/// a Copy Address button. The address is derived from the session's owner
/// key, so its presence (rather than its exact value) is what the regression
/// test asserts.
@MainActor
struct USDCDepositAddressScreen {

    private let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    // MARK: - Elements

    /// "Copy Address" CTA at the bottom of the screen. Flips its label to
    /// "Copied" after a successful tap.
    var copyAddressButton: XCUIElement {
        app.buttons["Copy Address"]
    }

    /// "Copied" success-state label that replaces "Copy Address" briefly
    /// after a successful copy.
    var copiedButton: XCUIElement {
        app.buttons["Copied"]
    }

    // MARK: - Assertions

    func assertReached(timeout: TimeInterval = 10) {
        XCTAssertTrue(
            copyAddressButton.waitForExistence(timeout: timeout),
            "Expected USDCDepositAddressScreen with 'Copy Address' CTA"
        )
    }
}
