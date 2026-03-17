//
//  CreateAccountSmokeTests.swift
//  FlipcashUITests
//

import XCTest

final class CreateAccountSmokeTests: BaseUITestCase {

    override var resetPermissions: [XCUIProtectedResource] { [.photos] }

    func testCreateAccount_saveToPhotos() {
        let createButton = app.buttons["Create a New Account"]
        XCTAssertTrue(createButton.waitForExistence(timeout: 10))
        createButton.tap()

        // AccessKeyScreen
        let saveButton = app.buttons["Save Access Key to Photos"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        saveButton.tap()

        // System "add to Photos" permission alert (belongs to Springboard)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allowButton = springboard.buttons["Allow"]
        if allowButton.waitForExistence(timeout: 5) {
            allowButton.tap()
        }

        // Should land on ScanScreen
        let giveButton = app.buttons["Give"]
        XCTAssertTrue(
            giveButton.waitForExistence(timeout: 15),
            "Expected to reach the main screen after account creation via Save to Photos"
        )
    }

    func testCreateAccount_wroteDownInstead() {
        let createButton = app.buttons["Create a New Account"]
        XCTAssertTrue(createButton.waitForExistence(timeout: 10))
        createButton.tap()

        // AccessKeyScreen
        let wroteDownButton = app.buttons["Wrote the 12 Words Down Instead?"]
        XCTAssertTrue(wroteDownButton.waitForExistence(timeout: 5))
        wroteDownButton.tap()

        // Confirmation dialog: "Are You Sure?"
        let confirmButton = app.buttons["Yes, I Wrote Them Down"]
        XCTAssertTrue(confirmButton.waitForExistence(timeout: 5))
        confirmButton.tap()

        // Should land on ScanScreen
        let giveButton = app.buttons["Give"]
        XCTAssertTrue(
            giveButton.waitForExistence(timeout: 15),
            "Expected to reach the main screen after account creation via Wrote Down"
        )
    }
}
