//
//  ProfileCreationSmokeTests.swift
//  FlipcashUITests
//

import XCTest

/// Drives profile creation end to end: Tips tab → intro → name → photo →
/// tipcard.
///
/// The photo step reaches the real blob pipeline, which is why the assertions
/// distinguish "the flow advanced" from "the upload succeeded" — see
/// `testCreateProfile`.
@MainActor
final class ProfileCreationSmokeTests: BaseUITestCase {

    override var requiresAuthentication: Bool { true }
    override var enabledBetaFlags: [String] { ["enableTips"] }

    func testTipsTabOpensTheProfileIntro() {
        assertMainScreenReached()

        waitAndTap(app.buttons["scan-tips-button"])

        XCTAssertTrue(
            app.buttons["start-receiving-tips-button"].waitForExistence(timeout: 30),
            "Expected the Tips intro when the account has no profile"
        )
        XCTAssertTrue(app.staticTexts["Receive Tips From Everyone"].exists)
    }

    func testNameStepGatesOnAValidName() {
        assertMainScreenReached()

        waitAndTap(app.buttons["scan-tips-button"])
        waitAndTap(app.buttons["start-receiving-tips-button"])

        let next = app.buttons["profile-name-next-button"]
        XCTAssertTrue(next.waitForExistence(timeout: 30), "Expected the name step")
        XCTAssertFalse(next.isEnabled, "Next must stay disabled until a name is entered")

        let field = app.textFields["Your Name"]
        waitAndTap(field)
        field.typeText("Ted Livingston")

        XCTAssertTrue(next.isEnabled, "Next must enable once the name is valid")
    }

    func testCreateProfile() throws {
        assertMainScreenReached()

        waitAndTap(app.buttons["scan-tips-button"])
        waitAndTap(app.buttons["start-receiving-tips-button"])

        let field = app.textFields["Your Name"]
        waitAndTap(field)
        // Unique per run so a re-run isn't a no-op against an account that
        // already carries the previous name.
        field.typeText("Ted \(Int(Date().timeIntervalSince1970) % 100_000)")

        let next = app.buttons["profile-name-next-button"]
        waitAndTap(next)

        // The name step calls SetDisplayName before advancing, so the photo step
        // appearing is also proof the name was accepted and moderated.
        let picker = app.buttons["profile-photo-picker"]
        XCTAssertTrue(
            picker.waitForExistence(timeout: 60),
            "Expected the photo step — SetDisplayName either failed or was rejected"
        )

        let photoNext = app.buttons["profile-photo-next-button"]
        XCTAssertFalse(photoNext.isEnabled, "Next must stay disabled until a photo is chosen")

        guard selectFirstPhotoFromLibrary(via: picker) else {
            throw XCTSkip("No photo available in the simulator library — skipping the upload half")
        }

        XCTAssertTrue(
            photoNext.waitForExistence(timeout: 30) && photoNext.isEnabled,
            "Next must enable once a photo is chosen"
        )
        photoNext.tap()

        // Upload → CompleteExternalUpload → poll until READY, bounded at 60s in
        // the app. The tipcard is the Tips root once the profile is complete.
        XCTAssertTrue(
            app.otherElements["tipcard"].waitForExistence(timeout: 120)
                || app.staticTexts["Share Your Tipcard to Get Tipped"].waitForExistence(timeout: 5),
            "Expected the tipcard after the photo upload completed"
        )
        XCTAssertTrue(app.buttons["tipcard-share-button"].exists, "Expected the Share action")
    }

    // MARK: - Helpers

    /// Picks the first photo out of the system library and confirms the crop
    /// editor. Returns false when the library is empty, which is the state of a
    /// freshly created simulator.
    private func selectFirstPhotoFromLibrary(via picker: XCUIElement) -> Bool {
        picker.tap()

        // The Menu presents Photo Library / Choose File.
        waitAndTap(app.buttons["Photo Library"])

        // UIImagePickerController runs out of process on iOS 11+, so the grid
        // may belong to the picker host rather than to `app`. Naming a bundle
        // scopes the query without stealing foreground, and a query against a
        // process that isn't running just returns an empty hierarchy — so
        // polling every candidate is safe.
        let hosts = [
            app,
            XCUIApplication(bundleIdentifier: "com.apple.PhotosUIPrivate.PhotosUIExtension"),
            XCUIApplication(bundleIdentifier: "com.apple.mobileslideshow"),
        ]
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

        let deadline = Date().addingTimeInterval(45)
        while Date() < deadline {
            // A reset authorization can still surface an access prompt.
            for allow in [springboard.buttons["Allow Full Access"], springboard.buttons["Allow Access to All Photos"], springboard.buttons["OK"]] {
                if allow.exists, allow.isHittable { allow.tap() }
            }

            for host in hosts {
                let cell = host.collectionViews.cells.firstMatch
                guard cell.exists, cell.isHittable else { continue }
                cell.tap()

                // `allowsEditing` presents a crop editor; "Choose" commits it.
                for confirm in hosts.map({ $0.buttons["Choose"] }) {
                    if confirm.waitForExistence(timeout: 10), confirm.isHittable {
                        confirm.tap()
                        return true
                    }
                }
                return true
            }

            Thread.sleep(forTimeInterval: 0.25)
        }

        return false
    }
}
