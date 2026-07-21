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
        // The tipcard is the Tips root once the profile is complete.
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
    }

    // MARK: - Helpers

    /// Picks the newest photo from the system library and commits the crop
    /// editor. Returns false when the library is empty, which is the state of a
    /// freshly created simulator.
    private func selectFirstPhotoFromLibrary(via picker: XCUIElement) -> Bool {
        picker.tap()

        // The Menu offers Photo Library / Choose File.
        waitAndTap(app.buttons["Photo Library"])

        // The library is a remote view hosted inside the app's own hierarchy, so
        // it is reachable from `app` rather than a separate process. Its
        // thumbnails are images tagged `PXGGridLayout-Info` — they are not
        // collection-view cells, and querying `cells` finds nothing. The head of
        // the grid is always on screen; thumbnails further down are in the tree
        // but below the fold, so a coordinate tap on them lands nowhere.
        let thumbnail = app.images.matching(identifier: "PXGGridLayout-Info").firstMatch
        guard thumbnail.waitForExistence(timeout: 30) else { return false }

        if thumbnail.isHittable {
            thumbnail.tap()
        } else {
            thumbnail.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }

        // `allowsEditing` puts a crop editor in front of the selection; "Choose"
        // is what actually returns the image.
        let choose = app.buttons["Choose"]
        guard choose.waitForExistence(timeout: 20) else { return false }
        choose.tap()

        return true
    }

    /// Everything legible on screen, for failure messages.
    private func visibleText() -> String {
        app.staticTexts.allElementsBoundByIndex
            .prefix(15)
            .map(\.label)
            .filter { !$0.isEmpty }
            .joined(separator: " | ")
    }
}
