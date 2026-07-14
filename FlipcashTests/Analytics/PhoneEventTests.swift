//
//  PhoneEventTests.swift
//  FlipcashTests
//

import Testing
@testable import Flipcash

@MainActor
@Suite("Phone analytics event contract")
struct PhoneEventTests {

    @Test("Phone event names match the cross-platform (Android) contract")
    func phoneEvent_eventNames_matchAndroid() {
        #expect(Analytics.PhoneEvent.entered.eventName == "Entered Phone Number")
        #expect(Analytics.PhoneEvent.verified.eventName == "Verified Phone Number")
    }
}
