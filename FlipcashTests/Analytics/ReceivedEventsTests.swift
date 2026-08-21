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
}
