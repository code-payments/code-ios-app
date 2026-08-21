//
//  ReceivedEventsTests.swift
//  FlipcashTests
//

import Testing
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("Received & origin event contract")
struct ReceivedEventsTests {

    @Test("Tip origin property values are shared verbatim with Android")
    func tipOriginValues() {
        #expect(TipOrigin.tipcard.analyticsValue == "Tipcard")
        #expect(TipOrigin.chat.analyticsValue == "Chat")
    }

    @Test("Display name event names are the shared contract")
    func displayNameEventNames() {
        #expect(Analytics.DisplayNameEvent.set.eventName == "Display Name Set")
        #expect(Analytics.DisplayNameEvent.updated.eventName == "Display Name Updated")
    }

    @Test("Display name sources are shared verbatim with Android")
    func displayNameSourceValues() {
        #expect(Analytics.DisplayNameSource.onboarding.analyticsValue == "Onboarding")
        #expect(Analytics.DisplayNameSource.myAccount.analyticsValue == "My Account")
        #expect(Analytics.DisplayNameSource.tipCardSetup.analyticsValue == "Tip Card Setup")
    }

    @Test("A first name is Set, a replacement is Updated", arguments: [
        (false, Analytics.DisplayNameEvent.set),
        (true, Analytics.DisplayNameEvent.updated),
    ])
    func setVersusUpdated(_ hadPreviousName: Bool, _ expected: Analytics.DisplayNameEvent) {
        #expect(Analytics.displayNameEvent(hadPreviousName: hadPreviousName) == expected)
    }
}
