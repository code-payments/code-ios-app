//
//  LinkCardFeedTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

/// What a card on screen is told, and when. The regression behind all of it: the transcript used to
/// resolve every card in its load pass and hold first paint until they landed, so one slow link kept
/// a whole screen blank and every answer re-diffed the window.
@MainActor
@Suite struct LinkCardFeedTests {

    private static func cashCard(_ entropy: String) -> LinkCard {
        .cash(
            LinkCard.Cash(
                url: URL(string: "https://send.flipcash.com/c/#/e=\(entropy)")!,
                entropy: entropy,
                range: NSRange(location: 0, length: 54)
            )
        )
    }

    nonisolated private static func resolved(
        _ amount: String,
        claim: LinkCard.Cash.Claim = .claimed
    ) -> LinkCard.Cash.Resolved {
        LinkCard.Cash.Resolved(amount: amount, claim: claim, tokenName: "Dollars", iconURL: nil)
    }

    private static func feed(
        memo: LinkCardMemo = LinkCardMemo(),
        claims: CashLinkClaimLog = CashLinkClaimLog(),
        cash: @escaping @Sendable (String) async throws -> LinkCard.Cash.Resolved
    ) -> LinkCardFeed {
        LinkCardFeed(
            resolver: LinkCardResolver(
                cashLookup: cash,
                mintLookup: { _ in
                    Issue.record("the mint lookup was called")
                    throw CancellationError()
                },
                groupLookup: { _ in
                    Issue.record("the group lookup was called")
                    throw CancellationError()
                }
            ),
            memo: memo,
            claims: claims,
            groups: UnusedGroups()
        )
    }

    /// These tests show cash cards only.
    private final class UnusedGroups: GroupLinkPresenting {
        func present(_ facts: GroupLinkFacts) -> LinkCard.Group.Resolved {
            Issue.record("a group card was presented")
            return LinkCard.Group.Resolved(title: "", memberCount: "", avatarID: "", imageData: nil, blurHash: nil, requirement: nil)
        }
        func loadPicture(for facts: GroupLinkFacts) async {}
    }

    /// What the card view does: subscribe, and paint whatever arrives.
    @MainActor
    private final class Inbox {
        private(set) var states: [LinkCard.State] = []
        private var task: Task<Void, Never>?

        init(_ stream: AsyncStream<LinkCard.State>) {
            task = Task { [weak self] in
                for await state in stream { self?.states.append(state) }
            }
        }

        func stop() { task?.cancel() }
    }

    /// Runs until `condition` holds or gives up, because the feed answers through tasks it owns
    /// rather than on the caller's turn. Bounded so a broken feed fails the test instead of hanging
    /// it.
    @discardableResult
    private func settle(until condition: () -> Bool) async -> Bool {
        for _ in 0..<200 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    @Test func aCardWithNothingKnownShimmersUntilTheAnswerArrives() async {
        let card = Self.cashCard("abc")
        let feed = Self.feed { entropy in Self.resolved("$\(entropy)") }

        #expect(feed.known(card) == nil, "nothing known yet is what puts the shimmer up")

        let inbox = Inbox(feed.states(for: card))
        defer { inbox.stop() }

        #expect(await settle { !inbox.states.isEmpty })
        #expect(inbox.states == [.cash(.resolved(Self.resolved("$abc")))])
        #expect(feed.known(card) == .cash(.resolved(Self.resolved("$abc"))))
    }

    /// The second visit to a link is the one that must not shimmer: the memo answers before the row
    /// draws, and the subscription still runs so a later claim can reach it.
    @Test func aRememberedAnswerPaintsWithoutWaiting() async {
        let memo = LinkCardMemo()
        let card = Self.cashCard("abc")
        memo.record(.cash(.resolved(Self.resolved("$15.00"))), for: card.resolutionKey)

        let feed = Self.feed(memo: memo) { _ in Self.resolved("$15.00") }
        #expect(feed.known(card) == .cash(.resolved(Self.resolved("$15.00"))))
    }

    /// A failure reaches the card — that is what stops the shimmer — but is not written down, so
    /// the next row to show this link asks again rather than inheriting one bad moment offline.
    @Test func aFailedLookupStopsTheShimmerAndIsNotRemembered() async {
        struct Offline: Error {}
        let card = Self.cashCard("offline")
        let feed = Self.feed { _ in throw Offline() }

        let inbox = Inbox(feed.states(for: card))
        defer { inbox.stop() }

        #expect(await settle { !inbox.states.isEmpty })
        #expect(inbox.states == [.cash(.unresolved)])
        #expect(feed.known(card) == nil)
    }

    /// Two rows quoting one link. One query, two cards — the guarantee that used to belong to the
    /// load coordinator's in-flight set.
    @Test func twoRowsQuotingOneLinkMakeOneQuery() async {
        let counter = Counter()
        let card = Self.cashCard("abc")
        let feed = Self.feed { _ in
            await counter.increment()
            return Self.resolved("$15.00")
        }

        let first = Inbox(feed.states(for: card))
        let second = Inbox(feed.states(for: card))
        defer { first.stop(); second.stop() }

        #expect(await settle { !first.states.isEmpty && !second.states.isEmpty })
        #expect(first.states == second.states)
        #expect(await counter.value == 1)
    }

    /// The sheet claims the link and the transcript behind it is still reading "Tap to claim". A
    /// settled claim is the one moment the answer is known to be wrong.
    @Test func aSettledClaimReachesTheCardOnScreen() async {
        let claims = CashLinkClaimLog()
        let counter = Counter()
        let card = Self.cashCard("abc")
        let feed = Self.feed(claims: claims) { _ in
            await counter.increment()
            return Self.resolved("$15.00", claim: await counter.value == 1 ? .claimable : .claimed)
        }

        let inbox = Inbox(feed.states(for: card))
        defer { inbox.stop() }
        #expect(await settle { !inbox.states.isEmpty })

        claims.record(entropy: "abc", collected: true)

        #expect(await settle { inbox.states.count == 2 })
        #expect(inbox.states.last == .cash(.resolved(Self.resolved("$15.00", claim: .claimed))))
    }

    /// Nobody tells this device about a link claimed on someone else's, so a card the reader can
    /// still act on asks again while they are looking at it.
    @Test func aClaimableCardAsksAgainOnTheCadence() async {
        let counter = Counter()
        let card = Self.cashCard("abc")
        let feed = Self.feed { _ in
            await counter.increment()
            return Self.resolved("$15.00", claim: await counter.value == 1 ? .claimable : .claimed)
        }

        let inbox = Inbox(feed.states(for: card))
        defer { inbox.stop() }
        #expect(await settle { !inbox.states.isEmpty })

        feed.refreshClaimable()

        #expect(await settle { inbox.states.count == 2 })
        #expect(inbox.states.last == .cash(.resolved(Self.resolved("$15.00", claim: .claimed))))
    }

    /// Claimed and expired are terminal. Asking again spends a request on an answer that cannot
    /// have moved.
    @Test func aSettledCardIsLeftOutOfTheCadence() async {
        let counter = Counter()
        let card = Self.cashCard("abc")
        let feed = Self.feed { _ in
            await counter.increment()
            return Self.resolved("$15.00", claim: .claimed)
        }

        let inbox = Inbox(feed.states(for: card))
        defer { inbox.stop() }
        #expect(await settle { !inbox.states.isEmpty })

        feed.refreshClaimable()
        try? await Task.sleep(for: .milliseconds(50))

        #expect(await counter.value == 1)
        #expect(inbox.states.count == 1)
    }

    /// A row that scrolls away stops being asked for. The cadence is for what the reader is looking
    /// at, not for every link the window has ever held.
    @Test func aRecycledRowDropsOutOfTheCadence() async {
        let counter = Counter()
        let card = Self.cashCard("abc")
        let feed = Self.feed { _ in
            await counter.increment()
            return Self.resolved("$15.00", claim: .claimable)
        }

        let inbox = Inbox(feed.states(for: card))
        #expect(await settle { !inbox.states.isEmpty })

        // Cancelling the read terminates the stream, and the termination handler hops back to the
        // main actor to drop the row, so the unsubscribe lands a turn later.
        inbox.stop()
        try? await Task.sleep(for: .milliseconds(50))

        feed.refreshClaimable()
        try? await Task.sleep(for: .milliseconds(50))

        #expect(await counter.value == 1)
    }

    private actor Counter {
        private(set) var value = 0
        func increment() { value += 1 }
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

    /// Forgetting is how a settled claim stops the next row painting "Tap to claim" for cash that
    /// has already been collected.
    @Test func aForgottenAnswerIsGone() {
        let memo = LinkCardMemo()
        memo.record(.cash(.unresolved), for: "cash:abc")
        memo.forget("cash:abc")
        #expect(memo.states["cash:abc"] == nil)
    }
}
