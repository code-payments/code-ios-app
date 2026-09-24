//
//  ReadProgressTests.swift
//  FlipcashCoreTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
@testable import FlipcashCore

@Suite("Read progress")
struct ReadProgressTests {

    private func inbound(_ id: UInt64) -> ReadProgress.VisibleMessage {
        ReadProgress.VisibleMessage(id: MessageID(value: id), isFromSelf: false)
    }

    private func own(_ id: UInt64) -> ReadProgress.VisibleMessage {
        ReadProgress.VisibleMessage(id: MessageID(value: id), isFromSelf: true)
    }

    @Test("The newest inbound message on screen is the one seen")
    func highestInboundWins() {
        #expect(ReadProgress.highestSeenInbound([inbound(3), inbound(7), inbound(5)]) == MessageID(value: 7))
    }

    @Test("The viewer's own messages don't count, however new")
    func ownMessagesAreIgnored() {
        #expect(ReadProgress.highestSeenInbound([inbound(3), own(9)]) == MessageID(value: 3))
        #expect(ReadProgress.highestSeenInbound([own(4), own(9)]) == nil)
    }

    @Test("Nothing on screen reports nothing")
    func emptyScreenReportsNothing() {
        var progress = ReadProgress()
        #expect(progress.advance(seeing: []) == nil)
        #expect(progress.reported == nil)
    }

    @Test("A report only moves forward within a visit")
    func neverGoesBackward() {
        var progress = ReadProgress()
        #expect(progress.advance(seeing: [inbound(5), inbound(6)]) == MessageID(value: 6))
        // Scrolled back up: older rows are on screen, and nothing new is reported.
        #expect(progress.advance(seeing: [inbound(2), inbound(3)]) == nil)
        // The same screen again reports nothing either.
        #expect(progress.advance(seeing: [inbound(6)]) == nil)
        #expect(progress.advance(seeing: [inbound(6), inbound(8)]) == MessageID(value: 8))
        #expect(progress.reported == MessageID(value: 8))
    }
}
