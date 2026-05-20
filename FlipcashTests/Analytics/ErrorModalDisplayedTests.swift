//
//  ErrorModalDisplayedTests.swift
//  FlipcashTests
//

import Testing
@testable import Flipcash

@MainActor
@Suite("Error Modal Displayed contract")
struct ErrorModalDisplayedTests {

    @Test("modalDisplayed event name is \"Error Modal Displayed\"")
    func modalDisplayed_eventName_isExpected() {
        #expect(Analytics.ErrorEvent.modalDisplayed.eventName == "Error Modal Displayed")
    }

    @Test("Property keys have the expected raw values")
    func propertyKeys_rawValues_areExpected() {
        #expect(Analytics.Property.title.rawValue == "Title")
        #expect(Analytics.Property.message.rawValue == "Message")
        #expect(Analytics.Property.screen.rawValue == "Screen")
        #expect(Analytics.Property.callSite.rawValue == "Call Site")
    }
}
