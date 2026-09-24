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
}
