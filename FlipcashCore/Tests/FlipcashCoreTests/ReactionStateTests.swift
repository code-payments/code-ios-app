//
//  ReactionStateTests.swift
//  FlipcashCoreTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
@testable import FlipcashCore

/// Behavior of `ReactionState` that `reactions.json`'s merge vectors do not cover: persistence,
/// stray responses, and the strip's ordering inputs. The merge rules themselves are held by
/// `ReactionMergeVectorTests`.
@Suite("ReactionState")
struct ReactionStateTests {

    private static func entry(_ emoji: String, count: UInt64, version: UInt64, selfReacted: Bool = false, at: Date? = nil) -> ReactionState.SummaryEntry {
        ReactionState.SummaryEntry(emoji: emoji, count: count, selfReacted: selfReacted, version: version, selfReactedAt: at)
    }

    // MARK: - Codable

    @Test("Encoding keeps confirmed state, tombstones included, and drops pending taps")
    func codable_roundTrip_persistsConfirmedOnly() throws {
        var state = ReactionState()
        state.applySummary([Self.entry("👍", count: 1, version: 3), Self.entry("🔥", count: 2, version: 5, selfReacted: true, at: Date(timeIntervalSince1970: 100))])
        state.applyUpdate(emoji: "👍", actorIsSelf: false, added: false, count: 0, version: 4, reactedAt: nil)
        _ = state.tap("😂", at: Date(timeIntervalSince1970: 200))

        let decoded = try JSONDecoder().decode(ReactionState.self, from: JSONEncoder().encode(state))

        #expect(decoded.confirmed == state.confirmed)
        #expect(decoded.confirmed["👍"]?.count == 0)
        #expect(decoded.confirmed["👍"]?.version == 4)
        #expect(decoded.desired.isEmpty)
        #expect(decoded.inFlight.isEmpty)
        #expect(decoded.selfReactions == [SelfReaction(emoji: "🔥", reactedAt: Date(timeIntervalSince1970: 100))])
    }

    @Test("A decoded tombstone still rejects a late, older add")
    func codable_decodedTombstone_rejectsStaleAdd() throws {
        var state = ReactionState()
        state.applySummary([Self.entry("👍", count: 1, version: 3)])
        state.applyUpdate(emoji: "👍", actorIsSelf: false, added: false, count: 0, version: 4, reactedAt: nil)

        var decoded = try JSONDecoder().decode(ReactionState.self, from: JSONEncoder().encode(state))
        decoded.applyUpdate(emoji: "👍", actorIsSelf: false, added: true, count: 1, version: 3, reactedAt: nil)

        #expect(decoded.pills.isEmpty)
    }

    // MARK: - Responses

    @Test("A response with nothing in flight changes nothing")
    func respond_nothingInFlight_isNoOp() {
        var state = ReactionState()
        state.applySummary([Self.entry("👍", count: 1, version: 1)])
        let before = state

        let outcome = state.respond(emoji: "👍", result: .ok(count: 5, selfReacted: true, version: 9, selfReactedAt: nil))
        let failure = state.respond(emoji: "👍", result: .failed(.network))

        #expect(outcome.call == nil)
        #expect(outcome.error == nil)
        #expect(failure.call == nil)
        #expect(failure.error == nil)
        #expect(state == before)
    }

    // MARK: - Self reactions

    @Test("Self reactions carry the server's time, and a pending add carries the tap's")
    func selfReactions_reactedAt_comesFromServerOrTap() {
        var state = ReactionState()
        state.applySummary([
            Self.entry("👍", count: 2, version: 1, selfReacted: true, at: Date(timeIntervalSince1970: 100)),
            Self.entry("🔥", count: 1, version: 1),
        ])
        _ = state.tap("🔥", at: Date(timeIntervalSince1970: 300))

        let reactions = state.selfReactions.sorted { $0.reactedAt < $1.reactedAt }

        #expect(reactions == [
            SelfReaction(emoji: "👍", reactedAt: Date(timeIntervalSince1970: 100)),
            SelfReaction(emoji: "🔥", reactedAt: Date(timeIntervalSince1970: 300)),
        ])
    }

    @Test("A pending remove drops the emoji from self reactions")
    func selfReactions_pendingRemove_isExcluded() {
        var state = ReactionState()
        state.applySummary([Self.entry("👍", count: 2, version: 1, selfReacted: true, at: Date(timeIntervalSince1970: 100))])

        let call = state.tap("👍", at: Date(timeIntervalSince1970: 200))

        #expect(call == ReactionCall(op: .remove, emoji: "👍"))
        #expect(state.selfReactions.isEmpty)
    }

    @Test("Own reaction from another device takes the update's time; a removal clears it")
    func selfReactions_ownUpdate_tracksReactedAt() {
        var state = ReactionState()
        state.applyUpdate(emoji: "👍", actorIsSelf: true, added: true, count: 1, version: 1, reactedAt: Date(timeIntervalSince1970: 50))
        #expect(state.selfReactions == [SelfReaction(emoji: "👍", reactedAt: Date(timeIntervalSince1970: 50))])

        state.applyUpdate(emoji: "👍", actorIsSelf: true, added: false, count: 0, version: 2, reactedAt: nil)
        #expect(state.selfReactions.isEmpty)
        #expect(state.confirmed["👍"]?.selfReactedAt == nil)
    }

    @Test("Someone else's update keeps our reaction time")
    func selfReactions_otherActorUpdate_keepsReactedAt() {
        var state = ReactionState()
        state.applySummary([Self.entry("👍", count: 1, version: 1, selfReacted: true, at: Date(timeIntervalSince1970: 100))])

        state.applyUpdate(emoji: "👍", actorIsSelf: false, added: true, count: 2, version: 2, reactedAt: Date(timeIntervalSince1970: 500))

        #expect(state.selfReactions == [SelfReaction(emoji: "👍", reactedAt: Date(timeIntervalSince1970: 100))])
    }

    // MARK: - Boost

    @Test("A boost sets the emoji's total and the user's own boost on the pill")
    func boost_ownUpdate_marksPillBoosted() {
        var state = ReactionState()
        state.applyUpdate(emoji: "💯", actorIsSelf: true, added: true, count: 1, version: 1, reactedAt: Date(timeIntervalSince1970: 10), boostCents: 500, actorBoostCents: 500)

        #expect(state.pills.map(\.boost) == [ReactionBoost(total: 500)])
        #expect(state.pills.map(\.selfBoosted) == [true])
    }

    @Test("A plain add after a boost keeps the total, and our own later add keeps our boost")
    func boost_laterAdds_keepTotals() {
        var state = ReactionState()
        state.applyUpdate(emoji: "💯", actorIsSelf: true, added: true, count: 1, version: 1, reactedAt: nil, boostCents: 500, actorBoostCents: 500)
        state.applyUpdate(emoji: "💯", actorIsSelf: false, added: true, count: 2, version: 2, reactedAt: nil, boostCents: 500)
        state.applyUpdate(emoji: "💯", actorIsSelf: true, added: true, count: 2, version: 3, reactedAt: nil, boostCents: 500)

        #expect(state.confirmed["💯"]?.boostCents == 500)
        #expect(state.confirmed["💯"]?.selfBoostCents == 500)
    }

    @Test("Tapping a reaction the user boosted does not remove it")
    func boost_tapOwnBoosted_sendsNothing() {
        var state = ReactionState()
        state.applySummary([ReactionState.SummaryEntry(emoji: "💯", count: 1, selfReacted: true, version: 1, selfReactedAt: nil, boostCents: 100, selfBoostCents: 100)])

        #expect(state.tap("💯", at: Date()) == nil)
        #expect(state.pills.map(\.selfReacted) == [true])
    }

    @Test("Someone else's boost does not stop the user removing their own plain reaction")
    func boost_tapOthersBoosted_removes() {
        var state = ReactionState()
        state.applySummary([ReactionState.SummaryEntry(emoji: "💯", count: 2, selfReacted: true, version: 1, selfReactedAt: nil, boostCents: 100, selfBoostCents: 0)])

        #expect(state.tap("💯", at: Date()) == ReactionCall(op: .remove, emoji: "💯"))
    }

    @Test("A locally recorded boost shows at once and is not counted twice once the stream confirms it")
    func boost_recordOwn_thenStream_countsOnce() {
        var state = ReactionState()
        state.applySummary([ReactionState.SummaryEntry(emoji: "💯", count: 2, selfReacted: true, version: 1, selfReactedAt: nil, boostCents: 100, selfBoostCents: 0)])

        state.recordOwnBoost("💯", selfTotalCents: 500)
        #expect(state.confirmed["💯"]?.boostCents == 600)
        #expect(state.tap("💯", at: Date()) == nil)

        state.applyUpdate(emoji: "💯", actorIsSelf: true, added: true, count: 2, version: 2, reactedAt: nil, boostCents: 600, actorBoostCents: 500)
        state.recordOwnBoost("💯", selfTotalCents: 500)
        #expect(state.confirmed["💯"]?.boostCents == 600)
    }
}
