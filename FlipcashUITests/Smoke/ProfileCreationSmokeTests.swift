//
//  ProfileCreationSmokeTests.swift
//  FlipcashUITests
//

import XCTest

/// Drives profile creation end to end on a freshly registered account: Tips tab
/// → intro → name → photo → tipcard.
///
/// A profile is created once per account, so this registers a new one rather
/// than logging into a persistent account — otherwise the flow is only
/// reachable on the very first run.
@MainActor
final class ProfileCreationSmokeTests: BaseUITestCase {

    override var enabledBetaFlags: [String] { ["enableTips"] }

    override func setUp() async throws {
        try await super.setUp()
        // Registration plus a real photo upload runs past XCTest's 2-minute
        // default, which kills the test before any assertion can report.
        executionTimeAllowance = 360
    }

    func testCreateProfile() throws {
        createFreshAccount()

        waitAndTap(app.buttons["scan-tips-button"])

        let start = app.buttons["start-receiving-tips-button"]
        XCTAssertTrue(
            start.waitForExistence(timeout: 30),
            "Expected the Tips intro on an account with no profile"
        )
        XCTAssertTrue(app.staticTexts["Receive Tips From Everyone"].exists)
        start.tap()

        let next = app.buttons["profile-name-next-button"]
        XCTAssertTrue(next.waitForExistence(timeout: 30), "Expected the name step")
        XCTAssertFalse(next.isEnabled, "Next must stay disabled until a name is entered")

        let field = app.textFields["Your Name"]
        waitAndTap(field)
        field.typeText("Flipcash User \(Int.random(in: 1_000...9_999))")

        XCTAssertTrue(next.isEnabled, "Next must enable once the name is valid")
        next.tap()

        // The name step calls SetDisplayName before advancing, so reaching the
        // photo step is also proof the name was accepted and moderated.
        let picker = app.buttons["profile-photo-picker"]
        XCTAssertTrue(
            picker.waitForExistence(timeout: 60),
            "Expected the photo step — SetDisplayName failed or was rejected"
        )

        let photoNext = app.buttons["profile-photo-next-button"]
        XCTAssertFalse(photoNext.isEnabled, "Next must stay disabled until a photo is chosen")

        guard selectFirstPhotoFromLibrary(via: picker) else {
            throw XCTSkip("No photo in the simulator library — cannot finish creation")
        }

        XCTAssertTrue(photoNext.isEnabled, "Next must enable once a photo is chosen")
        photoNext.tap()

        // Upload, finalize, then poll until ready — bounded at 60s in the app.
        // Creation lands directly on the tipcard, pushed over the Tips list.
        guard app.staticTexts["Share Your Tipcard to Get Tipped"].waitForExistence(timeout: 90) else {
            // An upload failure surfaces as a dialog whose copy names the stage
            // that failed, so say what is actually on screen.
            XCTFail("Tipcard never appeared. On screen: [\(visibleText())]")
            return
        }

        XCTAssertTrue(app.buttons["tipcard-share-button"].exists, "Expected the Share action")
        XCTAssertTrue(
            app.buttons["tipcard-export-button"].waitForExistence(timeout: 30),
            "Expected the Export action once the card has rendered"
        )

        // Backing off the card reveals the conversation list — the Tips root.
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(
            app.buttons["show-my-tipcard-button"].waitForExistence(timeout: 15),
            "Expected the Tips conversation list beneath the tipcard"
        )
    }
}
