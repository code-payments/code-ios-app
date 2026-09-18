//
//  LinkCardLandingTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

/// How a transcript's card answers reach it. The card a reader waits on is the one these pin: a
/// lookup that is slow, or queued behind a slow one, is what leaves a blank ticket on screen.
@MainActor
@Suite struct LinkCardLandingTests {

    private static func cashCard(_ entropy: String) -> LinkCard {
        .cash(
            LinkCard.Cash(
                url: URL(string: "https://send.flipcash.com/c/#/e=\(entropy)")!,
                entropy: entropy,
                range: NSRange(location: 0, length: 54),
                state: .unresolved
            )
        )
    }

    nonisolated private static func resolved(_ amount: String) -> LinkCard.Cash.Resolved {
        LinkCard.Cash.Resolved(amount: amount, claim: .claimed, tokenName: "Dollars", iconURL: nil)
    }

    /// The regression this guards: the lookups used to run one after another and land as one batch,
    /// so a single slow link held every other card on the screen blank for as long as it took.
    @Test func aSlowCardDoesNotHoldTheOthersBlank() async {
        let resolver = LinkCardResolver(
            cashLookup: { entropy in
                if entropy == "slow" {
                    try? await Task.sleep(for: .milliseconds(200))
                }
                return Self.resolved(entropy)
            },
            mintLookup: { _ in Issue.record("the mint lookup was called"); throw CancellationError() }
        )

        var order: [String] = []
        await ConversationLoadCoordinator.land(
            [Self.cashCard("slow"), Self.cashCard("fast")],
            through: resolver
        ) { key, _ in
            order.append(key)
        }

        #expect(order == ["cash:fast", "cash:slow"], "the fast card has to draw without waiting on the slow one")
    }

    /// Every card lands exactly once, including one whose lookup failed — an unresolved answer is
    /// still an answer, and it is what stops a scrolling transcript asking again on every tick.
    @Test func everyCardLandsOnceIncludingAFailedLookup() async {
        struct Offline: Error {}
        let resolver = LinkCardResolver(
            cashLookup: { entropy in
                guard entropy != "offline" else { throw Offline() }
                return Self.resolved(entropy)
            },
            mintLookup: { _ in Issue.record("the mint lookup was called"); throw Offline() }
        )

        var landed: [String: LinkCard.State] = [:]
        await ConversationLoadCoordinator.land(
            [Self.cashCard("offline"), Self.cashCard("ok")],
            through: resolver
        ) { key, state in
            #expect(landed[key] == nil, "\(key) landed twice")
            landed[key] = state
        }

        #expect(landed.count == 2)
        #expect(landed["cash:offline"] == .cash(.unresolved))
        #expect(landed["cash:ok"] == .cash(.resolved(Self.resolved("ok"))))
    }
}

/// The memo is what a chat's first paint reads, so a card answered once never goes blank again.
@MainActor
@Suite struct LinkCardMemoTests {

    @Test func aRecordedAnswerReadsBack() {
        let memo = LinkCardMemo()
        #expect(memo.states.isEmpty)

        memo.record(.cash(.unresolved), for: "cash:abc")
        #expect(memo.states["cash:abc"] == .cash(.unresolved))
    }

    /// A re-ask exists because the old answer went stale, so the newest one wins outright.
    @Test func aReAskOverwritesWhatWasThere() {
        let memo = LinkCardMemo()
        let claimed = LinkCard.Cash.Resolved(amount: "$15.00", claim: .claimed, tokenName: "Dollars", iconURL: nil)

        memo.record(.cash(.unresolved), for: "cash:abc")
        memo.record(.cash(.resolved(claimed)), for: "cash:abc")

        #expect(memo.states["cash:abc"] == .cash(.resolved(claimed)))
    }
}
