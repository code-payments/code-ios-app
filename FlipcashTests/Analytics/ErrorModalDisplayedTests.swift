//
//  ErrorModalDisplayedTests.swift
//  FlipcashTests
//

import Testing
@testable import Flipcash

@MainActor
@Suite("Error Modal Displayed contract")
struct ErrorModalDisplayedTests {

    @Test("modalDisplayed raw value matches the Android contract exactly")
    func modalDisplayed_rawValue_matchesAndroidContract() {
        #expect(Analytics.ErrorEvent.modalDisplayed.eventName == "Error Modal Displayed")
    }

    @Test("Property keys match the Android contract exactly")
    func propertyKeys_rawValues_matchAndroidContract() {
        #expect(Analytics.Property.title.rawValue == "Title")
        #expect(Analytics.Property.message.rawValue == "Message")
        #expect(Analytics.Property.screen.rawValue == "Screen")
        #expect(Analytics.Property.callSite.rawValue == "Call Site")
    }
}
