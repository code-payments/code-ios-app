//
//  ReceivedEventsTests.swift
//  FlipcashTests
//

import Testing
@testable import Flipcash

@MainActor
@Suite("Received event contract")
struct ReceivedEventsTests {

    @Test("A first name is Set, a replacement is Updated", arguments: [
        (false, Analytics.DisplayNameEvent.set),
        (true, Analytics.DisplayNameEvent.updated),
    ])
    func setVersusUpdated(_ hadPreviousName: Bool, _ expected: Analytics.DisplayNameEvent) {
        #expect(Analytics.displayNameEvent(hadPreviousName: hadPreviousName) == expected)
    }

    @Test("Received event names are the shared contract")
    func receivedEventNames() {
        #expect(Analytics.ConversationEvent.tipReceived.eventName == "Tip Received")
    }

    @Test("Received counter names are the shared contract")
    func receivedCounterNames() {
        #expect(Analytics.ReceivedCounter.tips.rawValue == "Tips Received")
        #expect(Analytics.ReceivedCounter.tipsValue.rawValue == "Tips Received Value")
        #expect(Analytics.ReceivedCounter.messages.rawValue == "Messages Received")
    }
}
