//
//  TipsSmokeTests.swift
//  FlipcashUITests
//

import XCTest

/// Drives the tip sheet end to end without committing a transfer — every
/// affordance is exercised, nothing is sent. The tipcard deeplink stands in
/// for scanning, which a simulator camera can't do.
///
/// **Prerequisites:** the `FLIPCASH_UI_TEST_ACCESS_KEY` account needs a tip
/// profile and a nonzero giveable balance (the sheet's funds gate), and the
/// standing recipient below must keep its tip profile.
@MainActor
final class TipsSmokeTests: BaseUITestCase {

    /// The standing tip recipient's user id — a public identifier, the tip
    /// counterpart of "Raul Riera" in the send tests. From that account's
    /// tipcard link.
    private static let recipientID = "db4c2358-e706-484c-85df-3c90407096ea"

    override var requiresAuthentication: Bool { true }
    override var enabledBetaFlags: [String] { ["enableTips"] }

    override func setUp() async throws {
        try await super.setUp()
        // The deeplink retries call `app.open`, which relaunches the app if
        // it isn't foremost — and a relaunch replays the stored launch
        // arguments, whose `--ui-testing` nuke would log the account out
        // mid-test. Clear them so any relaunch resumes the session (the beta
        // flag survives via its on-disk cache).
        app.launchArguments = []
        // The full flow runs past XCTest's 2-minute default.
        executionTimeAllowance = 600
    }

    /// A tipcard link opened via deeplink lands the sender on the Send a Tip
    /// sheet over the recipient's card.
    func testTipDeeplink_showsTipSheet() throws {
        assertMainScreenReached()

        openTipSheet(for: Self.recipientID)

        XCTAssertTrue(app.buttons["Swipe to Tip"].exists, "Expected the Swipe to Tip control")
        XCTAssertTrue(app.buttons["tip-custom-chip"].exists, "Expected the custom amount chip")
    }

    /// Exercises every affordance on the tip sheet without committing a
    /// transfer: the presets render readable amounts, the "…" entry titles
    /// itself and adopts a value onto the chip, and both the fiat and tip
    /// currency pickers open and close. The swipe control is never dragged,
    /// so no money moves.
    func testTipDeeplink_allowsCustomizingValueAndCurrency() throws {
        assertMainScreenReached()

        openTipSheet(for: Self.recipientID)

        // The presets carry readable amounts from the server's flags.
        for tier in ["low", "medium", "high"] {
            let chip = app.buttons["tip-chip-\(tier)"]
            XCTAssertTrue(chip.exists, "Expected the \(tier) preset chip")
            XCTAssertFalse(chip.label.isEmpty, "Expected a readable amount on the \(tier) chip")
            XCTAssertNotEqual(chip.label, "–", "Expected a readable amount on the \(tier) chip")
        }
        XCTAssertTrue(app.buttons["Swipe to Tip"].exists, "Expected the Swipe to Tip control")

        // The "…" chip opens the titled amount entry.
        waitAndTap(app.buttons["tip-custom-chip"])
        let amountEntry = AmountEntryScreen(app: app)
        XCTAssertTrue(amountEntry.keypadButton("2").waitForExistence(timeout: 15), "Expected the amount keypad")
        XCTAssertTrue(app.navigationBars["Amount to Tip"].exists, "Expected the Amount to Tip title")

        // The flag opens the fiat currency picker; close it unchanged.
        waitAndTap(app.buttons["amount-currency-button"])
        XCTAssertTrue(app.navigationBars["Select Region"].waitForExistence(timeout: 10), "Expected the fiat picker")
        app.navigationBars["Select Region"].buttons["Close"].tap()

        // A value above the minimum lands on the custom chip — no send.
        XCTAssertTrue(amountEntry.keypadButton("2").waitForExistence(timeout: 10), "Expected the keypad back")
        amountEntry.keypadButton("2").tap()
        waitAndTap(app.buttons["Next"])

        let customChip = app.buttons["tip-custom-chip"]
        XCTAssertTrue(customChip.waitForExistence(timeout: 10), "Expected the sheet back after entry")
        XCTAssertTrue(customChip.label.contains("2"), "Expected the entered amount on the custom chip, got '\(customChip.label)'")

        // The tip currency dropdown opens the held-currency picker.
        waitAndTap(app.buttons["tip-currency-row"])
        XCTAssertTrue(app.navigationBars["Select Currency"].waitForExistence(timeout: 10), "Expected the tip currency picker")
        app.navigationBars["Select Currency"].buttons["Close"].tap()

        XCTAssertTrue(app.buttons["Swipe to Tip"].waitForExistence(timeout: 10), "Expected the sheet intact after customization")
    }

    // MARK: - Helpers

    /// Opens the tip link and rides out the freshly logged-in account's async
    /// loads on the way to the Send a Tip sheet. Balances can lag the link, so
    /// the "No Balance Yet" dialog is dismissed and the link reopened until
    /// they hydrate. A profile intro that appears resolves on its own once the
    /// account's (prerequisite) profile record loads — the parked tip resumes
    /// when its sheet closes. Never mutates the standing account.
    ///
    /// The custom scheme stands in for the universal link, which has no
    /// deterministic app association on the simulator.
    private func openTipSheet(for recipientID: String) {
        let link = URL(string: "flipcash://tip/\(recipientID)")!
        app.open(link)

        let sheet = app.staticTexts["Send a Tip"]
        let noBalance = app.staticTexts["No Balance Yet"]

        let deadline = Date().addingTimeInterval(180)
        while Date() < deadline {
            if sheet.exists { return }

            // Balances hadn't hydrated when the link was handled — dismiss
            // and reopen; the retry window gives the fetch time to land.
            if noBalance.exists {
                app.buttons["Cancel"].tap()
                Thread.sleep(forTimeInterval: 3)
                app.open(link)
                continue
            }

            Thread.sleep(forTimeInterval: 1)
        }

        XCTFail("The Send a Tip sheet never appeared. On screen: [\(visibleText())]")
    }
}
