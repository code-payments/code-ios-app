import Foundation
import Testing
@testable import FlipcashCore

/// Settle section of `test-vectors/reactions.json`: the pill order on screen over time, holds under a
/// touch, and taps just after a move, replayed against a fake clock.
@Suite struct ReactionSettleVectorTests {

    @Test func defaultsMatchTheCrossPlatformVectors() throws {
        let fixture = try loadReactionFixture()
        #expect(ReactionSettleConfig(fixture.settleDefaults) == .default)
        #expect(ReactionSettleConfig.default.tapGrace == ReactionSettleConfig.defaultTapGrace)
    }

    @Test func settleMatchesTheCrossPlatformVectors() throws {
        let fixture = try loadReactionFixture()
        #expect(fixture.settle.count == 16)

        for vector in fixture.settle {
            let clock = FakeClock()
            let config = ReactionSettleConfig(vector.config)
            var settler: ReactionSettler?
            let label = "vector `\(vector.name)`: \(vector.note)"

            for step in vector.steps {
                switch step {
                case .start(let at, let pills, let expect):
                    clock.now = .milliseconds(at)
                    settler = ReactionSettler(pills: Self.pills(pills), config: config, clock: { clock.now })
                    #expect(settler?.order == expect, "\(label) — start at \(at)")
                case .pills(let at, let pills):
                    clock.now = .milliseconds(at)
                    settler?.update(Self.pills(pills))
                case .touch(let at):
                    clock.now = .milliseconds(at)
                    settler?.touch()
                case .settle(let at, let expect):
                    clock.now = .milliseconds(at)
                    settler?.settle()
                    #expect(settler?.order == expect, "\(label) — settle at \(at)")
                case .hit(let at, let index, let expect):
                    clock.now = .milliseconds(at)
                    #expect(settler?.hit(slot: index) == expect, "\(label) — hit \(index) at \(at)")
                }
            }
        }
    }

    private static func pills(_ pills: [String: ReactionFixture.SettleVector.Pill]) -> [ReactionPill] {
        pills.map { emoji, pill in
            ReactionPill(
                emoji: emoji,
                count: pill.count,
                selfReacted: false,
                pending: false,
                boost: pill.boostTotal > 0 ? ReactionBoost(total: pill.boostTotal) : nil
            )
        }
    }
}

private final class FakeClock: @unchecked Sendable {
    var now: Duration = .zero
}

private extension ReactionSettleConfig {
    init(_ config: ReactionFixture.SettleConfig) {
        self.init(
            beat: .milliseconds(config.settleMs),
            maxSwaps: config.maxSwaps,
            countMargin: config.countMargin,
            flapCooldown: .milliseconds(config.flapCooldownMs),
            holdAfterTouch: .milliseconds(config.holdAfterTouchMs),
            maxHold: .milliseconds(config.maxHoldMs),
            tapGrace: .milliseconds(config.hitGraceMs)
        )
    }
}
