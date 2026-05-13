//
//  BuyPhantomRegressionTests.swift
//  FlipcashUITests
//

import XCTest

/// Regression test for the Phantom funding path. Exercises the in-app flow
/// as far as can be tested without a real Phantom install:
///
/// - The buy nested sheet opens on top of CurrencyInfoScreen.
/// - An amount above the USDF balance routes to `PurchaseMethodSheet`.
/// - Selecting Phantom on an account with no saved Phantom session pushes
///   `PhantomEducationScreen` (rather than skipping directly to the
///   Confirm screen — the no-session branch in `PurchaseMethodSheet`).
/// - The Connect CTA is hittable.
///
/// The test stops at the Connect tap. Driving the actual Phantom callback
/// is out of scope — `WalletCallbackRegressionTests` covers the deeplink
/// re-entry surface separately.
///
/// **Prerequisites:**
/// - A valid `FLIPCASH_UI_TEST_ACCESS_KEY` set in `secrets.local.xcconfig`
/// - The test account must NOT have a saved Phantom session in Keychain
///   (a fresh test account is fine; a previously-Phantom-connected account
///   would skip past `PhantomEducationScreen`).
final class BuyPhantomRegressionTests: BaseUITestCase {

    override var requiresAuthentication: Bool { true }

    func testPhantomFlow_newAccount_showsEducationScreen() {
        let wallet = WalletScreen(app: app)
        let currencyInfo = CurrencyInfoUIScreen(app: app)
        let amountEntry = AmountEntryScreen(app: app)
        let purchaseMethods = PurchaseMethodSheet(app: app)
        let phantomEducation = PhantomEducationScreen(app: app)

        assertMainScreenReached()

        // Navigate: Main → Wallet → first currency → CurrencyInfoScreen → Buy
        wallet.open(from: self)
        wallet.selectFirstCurrency()
        currencyInfo.assertReached()
        waitAndTap(currencyInfo.buyButton)

        // Enter a high amount so the USDF gate fails and the picker shows.
        amountEntry.enterPickerTriggeringAmount()
        waitUntilHittableAndTap(amountEntry.buyActionButton)

        // Picker → Phantom → PhantomEducationScreen (no saved session).
        purchaseMethods.assertReached()
        purchaseMethods.selectPhantom(from: self)

        phantomEducation.assertReached()
        XCTAssertTrue(
            phantomEducation.connectButton.isHittable,
            "Expected the Connect CTA to be hittable on the education screen"
        )
    }
}
