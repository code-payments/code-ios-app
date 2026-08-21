//
//  ConvertConfirmationUIScreen.swift
//  FlipcashUITests
//

import XCTest

/// Page object for `ConvertConfirmationScreen` — the fee breakdown and the
/// final Confirm button of the Convert flow.
@MainActor
struct ConvertConfirmationUIScreen {

    private let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    // MARK: - Elements

    var confirmButton: XCUIElement { app.buttons["Confirm"] }
    var conversionFeeRow: XCUIElement { app.staticTexts["Conversion fee"] }

    // MARK: - Actions

    func confirmConvert(from testCase: BaseUITestCase) {
        testCase.waitUntilHittableAndTap(confirmButton, timeout: 10, "Expected the Convert confirmation screen")
    }
}
