//
//  ProfileCreationSmokeTests.swift
//  FlipcashUITests
//

import XCTest

/// Covers profile creation and the tipcard it produces.
///
/// A profile is created once per account and the UI-test account persists
/// between runs, so these tests are written to be idempotent: the creation test
/// drives the full flow on an account that has no profile and verifies the
/// resulting tipcard on one that already does, and the upload pipeline is
/// exercised on every run through the Settings editor either way.
@MainActor
final class ProfileCreationSmokeTests: BaseUITestCase {

    override var requiresAuthentication: Bool { true }
    override var enabledBetaFlags: [String] { ["enableTips"] }

    override func setUp() async throws {
        try await super.setUp()
        // Login plus a real upload runs past XCTest's 2-minute default, which
        // kills the test before any assertion can report what went wrong.
        executionTimeAllowance = 360
    }

    // MARK: - Creation

    func testCreateProfile() throws {
        assertMainScreenReached()
        waitAndTap(app.buttons["scan-tips-button"])

        let intro = app.buttons["start-receiving-tips-button"]
        let tipcardHeading = app.staticTexts["Share Your Tipcard to Get Tipped"]

        XCTAssertTrue(
            waitForEither(intro, tipcardHeading, timeout: 30),
            "Tips opened on neither the creation intro nor the tipcard"
        )

        if intro.exists {
            XCTAssertTrue(app.staticTexts["Receive Tips From Everyone"].exists)
            try createProfile(from: intro)
        }

        XCTAssertTrue(
            tipcardHeading.waitForExistence(timeout: 90),
            "Expected the tipcard once the profile is complete"
        )
        XCTAssertTrue(app.buttons["tipcard-share-button"].exists, "Expected the Share action")
        XCTAssertTrue(app.buttons["tipcard-export-button"].waitForExistence(timeout: 30),
                      "Expected the Export action once the card has rendered")
    }

    /// Runs the whole upload pipeline — reserve, direct-to-storage POST,
    /// finalize, poll — on every run, regardless of whether the account already
    /// had a profile. This is the part that talks to the real server, so it is
    /// the part worth exercising repeatedly.
    func testReplaceProfilePhoto() throws {
        assertMainScreenReached()

        let settings = SettingsUIScreen(app: app)
        settings.open(from: self)
        settings.navigateToMyAccount(from: self)
        waitAndTap(app.buttons["Profile"])

        let avatar = app.buttons["settings-profile-photo"]
        XCTAssertTrue(avatar.waitForExistence(timeout: 30), "Expected the Profile editor")

        guard selectFirstPhotoFromLibrary(via: avatar, opensMenu: false) else {
            throw XCTSkip("No photo in the simulator library — nothing to upload")
        }

        // A rejected or failed upload surfaces as a dialog; success is its absence.
        let dismissedDialog = app.buttons["OK"]
        XCTAssertFalse(
            dismissedDialog.waitForExistence(timeout: 60),
            "Photo upload failed: \(visibleText())"
        )
    }

    // MARK: - Helpers

    private func createProfile(from intro: XCUIElement) throws {
        intro.tap()

        let field = app.textFields["Your Name"]
        waitAndTap(field)
        // Unique per run so a re-run isn't a no-op against an account that
        // already carries the previous name.
        field.typeText("Ted \(Int(Date().timeIntervalSince1970) % 100_000)")

        let next = app.buttons["profile-name-next-button"]
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

        guard selectFirstPhotoFromLibrary(via: picker, opensMenu: true) else {
            throw XCTSkip("No photo in the simulator library — cannot finish creation")
        }

        XCTAssertTrue(photoNext.isEnabled, "Next must enable once a photo is chosen")
        photoNext.tap()
    }

    /// Picks the newest photo from the system library and commits the crop
    /// editor. Returns false when the library is empty, which is the state of a
    /// freshly created simulator.
    private func selectFirstPhotoFromLibrary(via control: XCUIElement, opensMenu: Bool) -> Bool {
        control.tap()

        if opensMenu {
            // The creation step offers Photo Library / Choose File; the Settings
            // editor goes straight to the library.
            waitAndTap(app.buttons["Photo Library"])
        }

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

    /// Waits until either element exists, so a test can branch on whichever
    /// state the account is actually in.
    private func waitForEither(_ a: XCUIElement, _ b: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if a.exists || b.exists { return true }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return false
    }

    /// Everything legible on screen, for failure messages — an upload failure
    /// surfaces as a dialog whose copy names the stage that failed.
    private func visibleText() -> String {
        app.staticTexts.allElementsBoundByIndex
            .prefix(15)
            .map(\.label)
            .filter { !$0.isEmpty }
            .joined(separator: " | ")
    }
}
