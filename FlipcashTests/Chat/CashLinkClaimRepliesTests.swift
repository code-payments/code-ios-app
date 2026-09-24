//
//  CashLinkClaimRepliesTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

/// When a tapped cash link earns its sender a thank-you: only a claim this transcript started, and
/// only one that moved the money.
@MainActor
@Suite struct CashLinkClaimRepliesTests {

    private final class Replies {
        var sent: [MessageID] = []
    }

    private static func make(_ claims: CashLinkClaimLog, into replies: Replies) -> CashLinkClaimReplies {
        CashLinkClaimReplies(claims: claims) { replies.sent.append($0) }
    }

    // The observer re-arms on a hop, so a change lands a turn after the write. Polls for a positive
    // and waits out the same window for a negative.
    private func settle(until condition: () -> Bool = { false }) async -> Bool {
        for _ in 0..<40 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    @Test func aCollectedClaimRepliesToTheTappedMessage() async {
        let claims = CashLinkClaimLog()
        let replies = Replies()
        let subject = Self.make(claims, into: replies)

        subject.tapped(entropy: "abc", messageID: MessageID(value: 7))
        claims.record(entropy: "abc", collected: true)

        #expect(await settle { !replies.sent.isEmpty })
        #expect(replies.sent == [MessageID(value: 7)])
    }

    /// Already collected or expired: the reader got nothing, so there is nothing to thank for.
    @Test func aClaimThatDidNotCollectSendsNothing() async {
        let claims = CashLinkClaimLog()
        let replies = Replies()
        let subject = Self.make(claims, into: replies)

        subject.tapped(entropy: "abc", messageID: MessageID(value: 7))
        claims.record(entropy: "abc", collected: false)

        _ = await settle()
        #expect(replies.sent.isEmpty)
    }

    /// A link claimed from somewhere else — pasted, scanned, another chat — was not tapped here.
    @Test func aClaimNotTappedHereSendsNothing() async {
        let claims = CashLinkClaimLog()
        let replies = Replies()
        let subject = Self.make(claims, into: replies)

        subject.tapped(entropy: "abc", messageID: MessageID(value: 7))
        claims.record(entropy: "xyz", collected: true)

        _ = await settle()
        #expect(replies.sent.isEmpty)
    }

    /// Claims that settled before the transcript opened are old news, not this reader's tap.
    @Test func aClaimSettledBeforeOpeningIsNotReplayed() async {
        let claims = CashLinkClaimLog()
        claims.record(entropy: "abc", collected: true)
        let replies = Replies()
        let subject = Self.make(claims, into: replies)

        subject.tapped(entropy: "abc", messageID: MessageID(value: 7))
        claims.record(entropy: "def", collected: true)

        _ = await settle()
        #expect(replies.sent.isEmpty)
    }
}
