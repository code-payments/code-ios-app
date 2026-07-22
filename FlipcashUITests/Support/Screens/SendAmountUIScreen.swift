//
//  SendAmountUIScreen.swift
//  FlipcashUITests
//

import XCTest

/// Page object for the Send flow's "Swipe to Send" amount screen. Digit entry
/// uses the shared `AmountEntryScreen`.
@MainActor
struct SendAmountUIScreen {

    private let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    // MARK: - Elements

    /// The slide-to-commit control.
    var swipeToSend: XCUIElement { app.buttons["Swipe to Send"] }

    // MARK: - Actions

    /// Commits the send by dragging the knob across the track — a tap lands on
    /// the track and never moves it.
    func commit() {
        XCTAssertTrue(swipeToSend.waitForExistence(timeout: 15), "Expected the 'Swipe to Send' control")
        let knob = swipeToSend.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5))
        let end = swipeToSend.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5))
        knob.press(forDuration: 0.1, thenDragTo: end)
    }
}
