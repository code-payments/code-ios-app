//
//  WalletCallbackRegressionTests.swift
//  FlipcashUITests
//

import XCTest

final class WalletCallbackRegressionTests: BaseUITestCase {

    override var requiresAuthentication: Bool { true }

    /// Simulates Phantom returning a "walletConnected" callback while
    /// the user is on the CurrencyInfoScreen. The screen must remain
    /// visible — not reset to the root.
    func testWalletConnectedCallback_doesNotResetInterface() {
        let wallet = WalletScreen(app: app)
        let currencyInfo = CurrencyInfoUIScreen(app: app)
        let funding = FundingSelectionScreen(app: app)

        assertMainScreenReached()

        // Navigate to CurrencyInfoScreen → Buy → select Phantom
        wallet.open(from: self)
        wallet.selectFirstCurrency()
        currencyInfo.assertReached()
        waitAndTap(currencyInfo.buyButton)
        funding.selectPhantom(from: self)

        // Phantom would open here — simulate its redirect back
        // with a walletConnected callback. The encrypted payload
        // won't decrypt (no real Phantom session), but the
        // interface must NOT reset — that's the regression.
        let walletConnectedURL = URL(string: "https://app.flipcash.com/wallet/walletConnected?nonce=test&data=test")!
        XCUIDevice.shared.system.open(walletConnectedURL)

        // Verify we're still on CurrencyInfoScreen, not reset to root
        currencyInfo.assertReached(timeout: 5)
    }

    /// Simulates Phantom returning an error (user cancelled) after
    /// tapping Buy → Phantom. The screen must remain visible.
    func testWalletErrorCallback_doesNotResetInterface() {
        let wallet = WalletScreen(app: app)
        let currencyInfo = CurrencyInfoUIScreen(app: app)
        let funding = FundingSelectionScreen(app: app)

        assertMainScreenReached()

        // Navigate to CurrencyInfoScreen → Buy → select Phantom
        wallet.open(from: self)
        wallet.selectFirstCurrency()
        currencyInfo.assertReached()
        waitAndTap(currencyInfo.buyButton)
        funding.selectPhantom(from: self)

        // Simulate Phantom returning with errorCode=4001 (user cancelled)
        let walletErrorURL = URL(string: "https://app.flipcash.com/wallet/walletConnected?errorCode=4001")!
        XCUIDevice.shared.system.open(walletErrorURL)

        // Verify we're still on CurrencyInfoScreen
        currencyInfo.assertReached(timeout: 5)
    }
}
