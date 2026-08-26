//
//  ConvertFlowScreen.swift
//  FlipcashUITests
//

import XCTest

/// Page object for the convert flow: the amount screen pushed by
/// `.convertCurrency(mint)`, its destination picker sheet, and the confirmation
/// step. The processing screen is `SwapProcessingUIScreen`.
///
/// Convert moves value between balances the account already holds — the picker
/// lists every held balance except the source — so it is the tab-bar UI's route
/// for both selling a token into Dollars and buying more of a currency already
/// in the wallet.
@MainActor
struct ConvertFlowScreen {

    private let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    // MARK: - Amount step

    /// "Convert to [currency ▾]" — opens the destination picker. Both the
    /// amount and confirmation steps are titled "Convert", so this selector is
    /// what distinguishes the amount step; the confirmation step has no picker.
    var destinationButton: XCUIElement { app.buttons["convert-destination-button"] }

    // MARK: - Destination picker

    var pickerTitle: XCUIElement { app.staticTexts["Select Currency"] }

    /// The Dollars (USDF) row.
    var pickerDollarsRow: XCUIElement { app.buttons["currency-picker-row-usdf"] }

    /// The first non-Dollars row. The source is filtered out of the options, so
    /// this always resolves to a token other than the one being converted.
    var pickerFirstTokenRow: XCUIElement {
        app.buttons.matching(identifier: "currency-picker-row").firstMatch
    }

    // MARK: - Confirmation step

    var confirmButton: XCUIElement { app.buttons["Confirm"] }

    /// Every conversion carries a fee, so this row is unconditional — what the
    /// direction changes is whether the fee is added on top of the purchase
    /// (from Dollars) or taken out of the proceeds.
    var conversionFeeRow: XCUIElement { app.staticTexts["Conversion fee"] }

    // MARK: - Assertions

    func assertAmountStepReached(timeout: TimeInterval = 10) {
        XCTAssertTrue(
            destinationButton.waitForExistence(timeout: timeout),
            "Expected the Convert amount screen with its destination selector"
        )
    }

    func assertConfirmationReached(timeout: TimeInterval = 10) {
        XCTAssertTrue(
            conversionFeeRow.waitForExistence(timeout: timeout),
            "Expected the Convert confirmation screen"
        )
    }
}
