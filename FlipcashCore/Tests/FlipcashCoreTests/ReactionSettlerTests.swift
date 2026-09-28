//
//  ReactionSettlerTests.swift
//  FlipcashCoreTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
@testable import FlipcashCore

@Suite("ReactionSettler")
struct ReactionSettlerTests {

    /// A clock the test moves by hand.
    final class FakeClock: @unchecked Sendable {
        var now: Duration = .zero
    }

    private static func pill(_ emoji: String, _ count: UInt64, boost: UInt64? = nil, selfReacted: Bool = false) -> ReactionPill {
        ReactionPill(emoji: emoji, count: count, selfReacted: selfReacted, pending: false, boost: boost.map(ReactionBoost.init))
    }

    private static func settler(_ pills: [ReactionPill], clock: FakeClock) -> ReactionSettler {
        ReactionSettler(pills: pills, clock: { clock.now })
    }

    @Test("A count crossing 99 keeps its width until the beat, then widens")
    func countCrossingNinetyNineWaitsForTheBeat() {
        let clock = FakeClock()
        var settler = Self.settler([Self.pill("🔥", 99)], clock: clock)
        #expect(settler.pills.first?.countDigits == 2)

        clock.now = .milliseconds(300)
        settler.update([Self.pill("🔥", 100)])
        #expect(settler.pills.first?.pill.count == 99)
        #expect(settler.pills.first?.countDigits == 2)

        clock.now = .milliseconds(999)
        let settledEarly = settler.settle()
        #expect(!settledEarly)
        #expect(settler.pills.first?.countDigits == 2)

        clock.now = .milliseconds(1000)
        let settled = settler.settle()
        #expect(settled)
        #expect(settler.pills.first?.pill.count == 100)
        #expect(settler.pills.first?.countDigits == 3)
    }

    @Test("A count that fits the reserved width shows at once")
    func fittingCountShowsLive() {
        let clock = FakeClock()
        var settler = Self.settler([Self.pill("🔥", 3)], clock: clock)

        clock.now = .milliseconds(100)
        settler.update([Self.pill("🔥", 42)])
        #expect(settler.pills.first?.pill.count == 42)
        #expect(settler.pills.first?.countDigits == 2)
    }

    @Test("A count falling back under 100 keeps the wider room until the beat")
    func narrowingWaitsForTheBeat() {
        let clock = FakeClock()
        var settler = Self.settler([Self.pill("🔥", 100)], clock: clock)

        clock.now = .milliseconds(100)
        settler.update([Self.pill("🔥", 99)])
        #expect(settler.pills.first?.pill.count == 99)
        #expect(settler.pills.first?.countDigits == 3)

        clock.now = .milliseconds(1000)
        let settled = settler.settle()
        #expect(settled)
        #expect(settler.pills.first?.countDigits == 2)
    }

    @Test("A first boost waits for the beat, since it needs room the pill has not reserved")
    func firstBoostWaitsForTheBeat() {
        let clock = FakeClock()
        var settler = Self.settler([Self.pill("🔥", 3)], clock: clock)

        clock.now = .milliseconds(100)
        settler.update([Self.pill("🔥", 3, boost: 5)])
        #expect(settler.pills.first?.pill.boost == nil)
        #expect(settler.pills.first?.boostDigits == 0)

        clock.now = .milliseconds(1000)
        settler.settle()
        #expect(settler.pills.first?.pill.boost?.total == 5)
        #expect(settler.pills.first?.boostDigits == 1)
    }

    @Test("Self-reacted changes show at once and reserve no room")
    func selfReactedIsLiveAndWidthless() {
        let clock = FakeClock()
        var settler = Self.settler([Self.pill("🔥", 3)], clock: clock)
        let before = settler.pills.first

        clock.now = .milliseconds(100)
        settler.update([Self.pill("🔥", 4, selfReacted: true)])
        #expect(settler.pills.first?.pill.selfReacted == true)
        #expect(settler.pills.first?.countDigits == before?.countDigits)
        #expect(settler.pills.first?.boostDigits == before?.boostDigits)
    }

    @Test("A resize alone starts the tap grace against the old layout")
    func resizeStartsTapGrace() {
        let clock = FakeClock()
        var settler = Self.settler([Self.pill("🔥", 99)], clock: clock)

        settler.update([Self.pill("🔥", 100)])
        clock.now = .milliseconds(1000)
        let settled = settler.settle()
        #expect(settled)
        #expect(settler.isInTapGrace)

        clock.now = .milliseconds(1000) + ReactionSettleConfig.defaultTapGrace
        #expect(!settler.isInTapGrace)
    }

    @Test("A row at rest has no beat due; a waiting change does")
    func nextBeat() {
        let clock = FakeClock()
        var settler = Self.settler([Self.pill("😂", 5), Self.pill("🔥", 4)], clock: clock)
        #expect(settler.nextBeat == nil)

        clock.now = .milliseconds(200)
        settler.update([Self.pill("😂", 5), Self.pill("🔥", 6)])
        #expect(settler.nextBeat == .milliseconds(1000))

        clock.now = .milliseconds(1000)
        settler.settle()
        #expect(settler.order == ["🔥", "😂"])
        #expect(settler.nextBeat == nil)
    }

    @Test("A swap blocked by the cooldown sets the next beat to when it clears")
    func nextBeatWaitsForCooldown() {
        let clock = FakeClock()
        var settler = Self.settler([Self.pill("😂", 5), Self.pill("🔥", 4)], clock: clock)

        settler.update([Self.pill("😂", 5), Self.pill("🔥", 6)])
        clock.now = .milliseconds(1000)
        settler.settle()

        clock.now = .milliseconds(1200)
        settler.update([Self.pill("😂", 7), Self.pill("🔥", 6)])
        #expect(settler.nextBeat == .milliseconds(4000))
    }
}
