//
//  CurrencyCreationUIScreen.swift
//  FlipcashUITests
//

import XCTest

/// Page object for the currency-creation summary and the launch wizard's steps
/// up to Select Payment Currency.
///
/// Nothing here creates a currency or spends money. The wizard's server calls
/// before the payment step are one name-availability check and three moderation
/// requests, all read-only; the launch only starts once a payment row is tapped
/// and its confirmation dialog is accepted, which this page object deliberately
/// offers no action for.
@MainActor
struct CurrencyCreationUIScreen {

    private let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    // MARK: - Summary

    var summaryNavigationBar: XCUIElement { app.navigationBars["Create Your Currency"] }
    var getStartedButton: XCUIElement { app.buttons["Get Started"] }

    // MARK: - Wizard steps

    /// Every step's primary CTA carries the same label, and one step is on
    /// screen at a time, so this stays unambiguous.
    var nextButton: XCUIElement { app.buttons["Next"] }

    var nameField: XCUIElement { app.textFields["Currency Name"] }
    var descriptionField: XCUIElement { app.textFields["Description"] }

    /// The icon step's picker. Its label is a `CircleImage`, so there is no text
    /// to match on; matched against any element type because a `Menu` is not
    /// guaranteed to surface as a button.
    var iconPicker: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "currency-icon-picker").firstMatch
    }

    var photoLibraryMenuItem: XCUIElement { app.buttons["Photo Library"] }

    /// The confirmation step's CTA. Its label interpolates the launch cost
    /// ("Pay $20.00 to Create"), hence the identifier.
    var payToCreateButton: XCUIElement { app.buttons["launch-pay-button"] }

    // MARK: - Payment selection

    var paymentSelectionNavigationBar: XCUIElement { app.navigationBars["Select Payment Currency"] }

    /// The USDF payment row, present whenever the account holds USDF.
    var usdfPaymentRow: XCUIElement { app.buttons["launch-payment-row-usdf"] }

    /// The non-USDF payment rows.
    var tokenPaymentRows: XCUIElementQuery { app.buttons.matching(identifier: "launch-payment-row") }

    // MARK: - Actions

    /// Summary → the wizard's name step. Returns false when Get Started diverted
    /// to the Add Money prompt because no single balance covers the launch cost.
    func startWizard(from testCase: BaseUITestCase) -> Bool {
        testCase.waitUntilHittableAndTap(getStartedButton)

        let prompt = AddMoneyStartScreen(app: app).noBalanceTitle
        let deadline = Date().addingTimeInterval(20)
        while !nameField.exists && !prompt.exists && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.5)
        }
        return nameField.exists
    }

    /// Fills the name step and advances. The name has to be unused: the step
    /// checks availability against the server and refuses a taken one.
    func completeNameStep(name: String, from testCase: BaseUITestCase) {
        testCase.waitAndTap(nameField)
        nameField.typeText(name)
        testCase.waitUntilHittableAndTap(nextButton)
    }

    /// Picks the first image in the simulator's photo library, accepts the crop
    /// editor, and advances.
    ///
    /// Returns false when the library has nothing to pick — the step's Next is
    /// disabled until `state.selectedImage` is set, and there is no other way
    /// past it.
    func completeIconStep(from testCase: BaseUITestCase) -> Bool {
        testCase.waitAndTap(iconPicker)
        testCase.waitUntilHittableAndTap(photoLibraryMenuItem)

        // `ImagePickerWithEditor` stays on `UIImagePickerController` for its
        // crop editor, which grants read access without a permission prompt.
        let firstPhoto = app.collectionViews.cells.firstMatch
        guard firstPhoto.waitForExistence(timeout: 30) else { return false }
        firstPhoto.tap()

        // "Move and Scale" confirms with "Choose".
        testCase.waitUntilHittableAndTap(app.buttons["Choose"])

        // Moderation runs on Next, so the button spins for a beat afterwards.
        testCase.waitUntilHittableAndTap(nextButton)
        return true
    }

    func completeDescriptionStep(_ text: String, from testCase: BaseUITestCase) {
        testCase.waitAndTap(descriptionField)
        descriptionField.typeText(text)
        testCase.waitUntilHittableAndTap(nextButton)
    }

    /// The bill step only picks colours; its Next lives in the toolbar.
    func completeBillStep(from testCase: BaseUITestCase) {
        testCase.waitUntilHittableAndTap(nextButton)
    }

    /// Confirmation → Select Payment Currency. The CTA reads
    /// "Pay $X to Create"; it commits nothing, the payment row does.
    func advancePastConfirmation(from testCase: BaseUITestCase) {
        testCase.waitUntilHittableAndTap(payToCreateButton)
    }

    // MARK: - Assertions

    func assertSummaryReached(timeout: TimeInterval = 10) {
        XCTAssertTrue(
            summaryNavigationBar.waitForExistence(timeout: timeout),
            "Expected the currency creation summary screen"
        )
    }

    func assertPaymentSelectionReached(timeout: TimeInterval = 30) {
        XCTAssertTrue(
            paymentSelectionNavigationBar.waitForExistence(timeout: timeout),
            "Expected the Select Payment Currency step"
        )
    }
}
