//
//  ReactionSettler.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// The tuning for `ReactionSettler`. The defaults equal `settleDefaults` in the orchestrator's
/// `test-vectors/reactions.json`, and a vector test holds them there.
public struct ReactionSettleConfig: Hashable, Sendable {

    /// Positions and widths change at most once per beat; counts change live.
    public var beat: Duration
    /// Neighbour swaps per beat, nearest the top first.
    public var maxSwaps: Int
    /// The count lead a pill needs to pass its neighbour. Any boost lead passes.
    public var countMargin: UInt64
    /// How long a pair that just swapped cannot swap back.
    public var flapCooldown: Duration
    /// How long a touch on the row holds it still.
    public var holdAfterTouch: Duration
    /// The longest a hold lasts, counted from the touch that began it.
    public var maxHold: Duration
    /// How long after a layout change a tap still resolves against the layout before it.
    public var tapGrace: Duration

    /// The tap grace. Nobody has measured real thumbs on a phone yet: 450 ms is best for a thumb that
    /// re-aims when a pill moves, and 600 to 700 ms would be better if thumbs commit to what they saw
    /// about 200 ms before landing. Kept as one constant so that measurement can move it.
    public static let defaultTapGrace: Duration = .milliseconds(450)

    public static let `default` = ReactionSettleConfig(
        beat: .milliseconds(1000),
        maxSwaps: 3,
        countMargin: 1,
        flapCooldown: .milliseconds(3000),
        holdAfterTouch: .milliseconds(1500),
        maxHold: .milliseconds(4000),
        tapGrace: defaultTapGrace
    )

    public init(
        beat: Duration,
        maxSwaps: Int,
        countMargin: UInt64,
        flapCooldown: Duration,
        holdAfterTouch: Duration,
        maxHold: Duration,
        tapGrace: Duration
    ) {
        self.beat = beat
        self.maxSwaps = maxSwaps
        self.countMargin = countMargin
        self.flapCooldown = flapCooldown
        self.holdAfterTouch = holdAfterTouch
        self.maxHold = maxHold
        self.tapGrace = tapGrace
    }
}

/// A pill as the row shows it between beats: the values that fit the room reserved at the last beat,
/// and that room.
public struct SettledReactionPill: Hashable, Sendable, Identifiable {
    public var id: String { pill.emoji }

    /// The pill with `count` and `boost` as shown, which lag the live values only when those need
    /// more room than is reserved.
    public let pill: ReactionPill
    /// The digits the count has room for, at least two.
    public let countDigits: Int
    /// The digits the boost amount has room for; zero leaves no room for a boost.
    public let boostDigits: Int
}

/// The order and widths of a pill row on screen, catching up with `ReactionOrdering` on a beat so
/// the row does not reorder or reflow under a thumb.
///
/// Mirrors `Settler` in the orchestrator's `test-vectors/gen_reactions.py`, which generated the
/// `settle` vectors. Pure and driven by an injected clock, so tests can step time.
public struct ReactionSettler {

    public let config: ReactionSettleConfig

    /// The emoji on screen, in order.
    public private(set) var order: [String]

    private let clock: () -> Duration
    /// The latest merged pills. An emoji missing here has a count of 0.
    private var live: [String: ReactionPill]
    /// What each on-screen pill shows.
    private var shown: [String: ReactionPill]
    private var room: [String: Room]
    private var lastBeat: Duration
    private var holdStart: Duration?
    private var holdUntil: Duration?
    private var tapOrder: [String] = []
    private var tapGraceUntil: Duration?
    private var pairSwaps: [Pair: Duration] = [:]

    /// A row coming on screen: shows `pills` in `ReactionOrdering` exactly.
    public init(pills: [ReactionPill], config: ReactionSettleConfig = .default, clock: @escaping () -> Duration) {
        self.config = config
        self.clock = clock
        let live = Self.liveByEmoji(pills)
        self.live = live
        self.order = Self.target(live)
        self.shown = live
        self.room = live.mapValues(Room.init)
        self.lastBeat = clock()
    }

    // MARK: - Input

    /// Replaces the merged pills. Values that fit their pill's reserved room show at once; positions,
    /// joins, departures and widths wait for `settle()`.
    public mutating func update(_ pills: [ReactionPill]) {
        live = Self.liveByEmoji(pills)
        for emoji in order {
            let current = shown[emoji]!
            let next = live[emoji] ?? Self.emptied(emoji)
            let room = room[emoji]!
            shown[emoji] = ReactionPill(
                emoji: emoji,
                count: room.fitsCount(next.count) ? next.count : current.count,
                selfReacted: next.selfReacted,
                pending: next.pending,
                boost: room.fitsBoost(next.boostTotal) ? next.boost : current.boost
            )
        }
    }

    /// A touch-down anywhere on the row: holds it still, extending a hold already running up to its cap.
    public mutating func touch() {
        let now = clock()
        let holding = holdUntil.map { now < $0 } ?? false
        if !holding { holdStart = now }
        let extended = min(now + config.holdAfterTouch, holdStart! + config.maxHold)
        holdUntil = holding ? max(holdUntil!, extended) : extended
    }

    // MARK: - Beat

    /// Runs a beat if one is due and the row is not held: emptied pills leave, new ones join at the
    /// end, up to `maxSwaps` neighbour swaps move pills toward `ReactionOrdering`, and every pill's
    /// room and shown values catch up with the live ones.
    ///
    /// - Returns: whether the layout changed, which starts the tap grace.
    @discardableResult
    public mutating func settle() -> Bool {
        let now = clock()
        if let holdUntil, now < holdUntil { return false }
        guard now - lastBeat >= config.beat else { return false }
        lastBeat = now

        let before = order
        let roomBefore = room
        var next = order.filter { (live[$0]?.count ?? 0) > 0 }
        next += Self.target(live).filter { !next.contains($0) }

        var swaps = 0
        while swaps < config.maxSwaps, let i = firstSwap(in: next, at: now) {
            pairSwaps[Pair(next[i], next[i + 1])] = now
            next.swapAt(i, i + 1)
            swaps += 1
        }

        order = next
        shown = live.filter { next.contains($0.key) }
        room = shown.mapValues(Room.init)

        let changed = order != before || room != roomBefore
        if changed {
            tapOrder = before
            tapGraceUntil = now + config.tapGrace
        }
        return changed
    }

    /// When `settle()` next has something to do, or nil when the row is at rest.
    public var nextBeat: Duration? {
        let due: Duration?
        if Set(order) != Set(live.keys) || shown != live || room != live.mapValues(Room.init) {
            due = .zero
        } else {
            due = pendingSwapTime()
        }
        guard let due else { return nil }
        return max(due, lastBeat + config.beat, holdUntil ?? .zero)
    }

    // MARK: - Output

    /// The pills on screen, in order, as they show now.
    public var pills: [SettledReactionPill] {
        order.map { emoji in
            let room = room[emoji]!
            return SettledReactionPill(pill: shown[emoji]!, countDigits: room.countDigits, boostDigits: room.boostDigits)
        }
    }

    /// Whether a tap now resolves against the layout from before the last change.
    public var isInTapGrace: Bool {
        tapGraceUntil.map { clock() < $0 } ?? false
    }

    /// The emoji a tap on `slot` lands on, against the previous layout during the tap grace, or nil
    /// for the "+" pill or empty space past the last pill.
    public func hit(slot: Int) -> String? {
        let order = isInTapGrace ? tapOrder : order
        return order.indices.contains(slot) ? order[slot] : nil
    }

    // MARK: - Private

    /// The room a pill reserves at a beat: its count's digits, at least two, and its boost's.
    private struct Room: Hashable {
        let countDigits: Int
        let boostDigits: Int

        init(_ pill: ReactionPill) {
            countDigits = max(2, Self.digits(pill.count))
            boostDigits = pill.boostTotal == 0 ? 0 : Self.digits(pill.boostTotal)
        }

        func fitsCount(_ count: UInt64) -> Bool {
            Self.digits(count) <= countDigits
        }

        func fitsBoost(_ total: UInt64) -> Bool {
            total == 0 || Self.digits(total) <= boostDigits
        }

        private static func digits(_ value: UInt64) -> Int {
            String(value).count
        }
    }

    /// An unordered pair of emoji, for the swap-back cooldown.
    private struct Pair: Hashable {
        let low: String
        let high: String

        init(_ a: String, _ b: String) {
            if a.utf8.lexicographicallyPrecedes(b.utf8) { (low, high) = (a, b) } else { (low, high) = (b, a) }
        }
    }

    /// The first neighbour pair, from the top, where the lower pill passes the upper one and the pair
    /// is out of cooldown.
    private func firstSwap(in order: [String], at now: Duration) -> Int? {
        order.indices.dropLast().first { i in
            if let swapped = pairSwaps[Pair(order[i], order[i + 1])], now - swapped < config.flapCooldown {
                return false
            }
            return overtakes(order[i + 1], order[i])
        }
    }

    /// The earliest a neighbour pair that passes comes out of cooldown, or nil if none passes.
    private func pendingSwapTime() -> Duration? {
        order.indices.dropLast()
            .filter { overtakes(order[$0 + 1], order[$0]) }
            .map { i in pairSwaps[Pair(order[i], order[i + 1])].map { $0 + config.flapCooldown } ?? .zero }
            .min()
    }

    /// Whether `below` passes `above`: on any boost lead, or on a count lead of at least `countMargin`.
    private func overtakes(_ below: String, _ above: String) -> Bool {
        let below = live[below] ?? Self.emptied(below)
        let above = live[above] ?? Self.emptied(above)
        if below.boostTotal != above.boostTotal { return below.boostTotal > above.boostTotal }
        return below.count >= above.count && below.count - above.count >= config.countMargin
    }

    private static func target(_ live: [String: ReactionPill]) -> [String] {
        ReactionOrdering.sorted(live.values).map(\.emoji)
    }

    private static func liveByEmoji(_ pills: [ReactionPill]) -> [String: ReactionPill] {
        Dictionary(pills.filter { $0.count > 0 }.map { ($0.emoji, $0) }, uniquingKeysWith: { _, last in last })
    }

    /// An on-screen pill whose emoji has left the merged pills: it shows 0 until the next beat.
    private static func emptied(_ emoji: String) -> ReactionPill {
        ReactionPill(emoji: emoji, count: 0, selfReacted: false, pending: false)
    }
}

private extension ReactionPill {
    var boostTotal: UInt64 { boost?.total ?? 0 }
}
