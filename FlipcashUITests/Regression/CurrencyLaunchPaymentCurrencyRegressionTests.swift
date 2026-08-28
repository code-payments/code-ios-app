//
//  CurrencyLaunchPaymentCurrencyRegressionTests.swift
//  FlipcashUITests
//

import XCTest

/// Regression test for the launch wizard's Select Payment Currency step: the
/// USDF row must read "Dollars", the name the rest of the app uses for the
/// reserve mint, not the "USDF" symbol.
///
/// The step used to pass `usesSymbol: true` to `CurrencyBalanceRow`, which is
/// the deposit flow's convention for picking an on-chain asset. Deciding how to
/// pay for a launch is not that, and every other spend surface — Give, Convert,
/// Buy — labels the same mint "Dollars".
///
/// The label is chosen in the view, so `CurrencyPaymentSelectionViewModel`'s
/// unit tests cannot reach it; asserting it means walking the wizard.
///
/// Spends nothing. Reaching the payment step performs one name-availability
/// check and three moderation calls, all read-only — the launch itself only
/// starts on a payment row tap, which this test never makes.
///
/// **Prerequisites:**
/// - A valid `FLIPCASH_UI_TEST_ACCESS_KEY` set in `secrets.local.xcconfig`
/// - The test account must hold enough in a single currency to cover the launch
///   cost, otherwise Get Started gates on Add Money (the case
///   `CurrencyCreationGateRegressionTests` covers)
/// - The account must hold USDF, so the USDF row is drawn
/// - At least one image in the simulator's photo library, for the icon step
final class CurrencyLaunchPaymentCurrencyRegressionTests: BaseUITestCase {

    override var requiresAuthentication: Bool { true }

    func testPaymentSelection_usdfRowIsLabelledDollars() throws {
        let wallet = WalletScreen(app: app)
        let creation = CurrencyCreationUIScreen(app: app)

        assertMainScreenReached()

        // Wallet → Create a Currency → Create Your Currency summary.
        wallet.open(from: self)
        wallet.tapCreateCurrencyTile(from: self)
        creation.assertSummaryReached()

        guard creation.startWizard(from: self) else {
            throw XCTSkip("The standing account cannot afford the launch cost — Get Started gated on Add Money")
        }

        // `checkAvailability` runs against the server, so the name has to be
        // one no previous run took.
        creation.completeNameStep(name: Self.uniqueCurrencyName(), from: self)

        guard creation.completeIconStep(from: self) else {
            throw XCTSkip("The simulator's photo library is empty — the icon step can't be completed")
        }

        creation.completeDescriptionStep("UI test currency, never launched.", from: self)
        creation.completeBillStep(from: self)
        creation.advancePastConfirmation(from: self)

        creation.assertPaymentSelectionReached()

        let usdfRow = creation.usdfPaymentRow
        XCTAssertTrue(
            usdfRow.waitForExistence(timeout: 10),
            "Expected a USDF payment row. On screen: \(visibleText())"
        )

        // The row's label is its `CurrencyLabel` flattened: name, then amount.
        XCTAssertTrue(
            usdfRow.label.contains("Dollars"),
            "Expected the USDF payment row to be labelled Dollars, got: \(usdfRow.label)"
        )
        XCTAssertFalse(
            usdfRow.label.contains("USDF"),
            "Expected the USDF payment row not to use the USDF symbol, got: \(usdfRow.label)"
        )
    }

    // MARK: - Helpers

    /// A name no earlier run can have claimed. Kept short: the step caps input
    /// at its character limit and silently truncates past it.
    private static func uniqueCurrencyName() -> String {
        "UITest\(Int(Date().timeIntervalSince1970) % 1_000_000)"
    }
}
