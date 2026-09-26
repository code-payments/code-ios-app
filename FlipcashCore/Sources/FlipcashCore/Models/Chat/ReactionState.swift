//
//  ReactionState.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// One message's reactions: the server state last accepted per emoji, merged with the user's
/// pending taps.
///
/// This is `gen_reactions.py`'s `Model`, and `reactions.json`'s `merge` vectors hold it to that.
/// Server state (summary, stream update, successful response) is accepted only when its version is
/// strictly greater than the one held for that emoji. The displayed self state is the pending tap
/// when there is one, otherwise the confirmed one, so the stream never overwrites a pending tap.
///
/// Only `confirmed` is encoded: pending taps and in-flight calls do not survive a relaunch.
public struct ReactionState: Hashable, Sendable, Codable {

    /// The last server state accepted for one emoji.
    public struct Confirmed: Hashable, Sendable, Codable {
        public var count: UInt64
        public var selfReacted: Bool
        public var version: UInt64
        /// When the user reacted with this emoji, if they have; orders the strip and takes no part in
        /// the merge.
        public var selfReactedAt: Date?

        public init(count: UInt64, selfReacted: Bool, version: UInt64, selfReactedAt: Date?) {
            self.count = count
            self.selfReacted = selfReacted
            self.version = version
            self.selfReactedAt = selfReactedAt
        }
    }

    /// One emoji as a reaction summary lists it.
    public struct SummaryEntry: Hashable, Sendable {
        public let emoji: String
        public let count: UInt64
        public let selfReacted: Bool
        public let version: UInt64
        public let selfReactedAt: Date?

        public init(emoji: String, count: UInt64, selfReacted: Bool, version: UInt64, selfReactedAt: Date?) {
            self.emoji = emoji
            self.count = count
            self.selfReacted = selfReacted
            self.version = version
            self.selfReactedAt = selfReactedAt
        }
    }

    /// The accepted server state per emoji; a count of 0 is a tombstone that keeps the emptied
    /// emoji's version so a late, older add is still rejected.
    public private(set) var confirmed: [String: Confirmed] = [:]
    /// The self state the user last tapped to, per emoji, until the server settles it.
    public private(set) var desired: [String: Bool] = [:]
    /// Emoji with an add or remove call on the wire.
    public private(set) var inFlight: Set<String> = []
    /// When the user tapped each emoji whose `desired` state is on.
    private var desiredAt: [String: Date] = [:]

    private enum CodingKeys: String, CodingKey {
        case confirmed
    }

    public init() {}

    // MARK: - Server state

    /// Accepts a reaction summary, which lists only non-empty emoji: a held emoji it omits has
    /// emptied, unless a tap on it is pending.
    public mutating func applySummary(_ reactions: [SummaryEntry]) {
        let present = Set(reactions.map(\.emoji))
        for entry in reactions {
            accept(
                entry.emoji,
                Confirmed(count: entry.count, selfReacted: entry.selfReacted, version: entry.version, selfReactedAt: entry.selfReactedAt)
            )
        }
        for (emoji, held) in confirmed where !present.contains(emoji) && desired[emoji] == nil && held.count > 0 {
            confirmed[emoji]?.count = 0
            confirmed[emoji]?.selfReacted = false
            confirmed[emoji]?.selfReactedAt = nil
        }
    }

    /// Accepts one stream update; `count` is the emoji's new total, not a delta.
    public mutating func applyUpdate(emoji: String, actorIsSelf: Bool, added: Bool, count: UInt64, version: UInt64, reactedAt: Date?) {
        let selfReacted: Bool
        let selfReactedAt: Date?
        if actorIsSelf {
            selfReacted = added
            selfReactedAt = added ? reactedAt : nil
        } else {
            selfReacted = confirmed[emoji]?.selfReacted ?? false
            selfReactedAt = confirmed[emoji]?.selfReactedAt
        }
        accept(emoji, Confirmed(count: count, selfReacted: selfReacted, version: version, selfReactedAt: selfReactedAt))
    }

    /// Accepts every emoji `other` has confirmed, each by version as any server state is, and
    /// ignores its pending taps.
    public mutating func merge(_ other: ReactionState) {
        for (emoji, state) in other.confirmed {
            accept(emoji, state)
        }
    }

    /// The confirmed non-empty emoji, as a summary would list them.
    public var summaryEntries: [SummaryEntry] {
        confirmed.compactMap { emoji, state in
            guard state.count > 0 else { return nil }
            return SummaryEntry(emoji: emoji, count: state.count, selfReacted: state.selfReacted, version: state.version, selfReactedAt: state.selfReactedAt)
        }
    }

    /// Whether no tap is pending and no call is on the wire.
    public var isSettled: Bool {
        desired.isEmpty && inFlight.isEmpty
    }

    // MARK: - User actions

    /// Flips the displayed self state of `emoji` and returns the call to send, or nil when a call
    /// for it is already on the wire and the response will send any follow-up.
    public mutating func tap(_ emoji: String, at date: Date) -> ReactionCall? {
        let on = !displayedSelf(emoji)
        desired[emoji] = on
        desiredAt[emoji] = on ? date : nil
        guard !inFlight.contains(emoji) else { return nil }
        return send(emoji)
    }

    /// Settles the call in flight for `emoji`, returning a coalesced follow-up call and the error to
    /// show, if any; a response for an emoji with nothing in flight is ignored.
    public mutating func respond(emoji: String, result: ReactionResult) -> (call: ReactionCall?, error: ReactionError?) {
        guard inFlight.remove(emoji) != nil else { return (nil, nil) }
        switch result {
        case .ok(let count, let selfReacted, let version, let selfReactedAt):
            accept(emoji, Confirmed(count: count, selfReacted: selfReacted, version: version, selfReactedAt: selfReactedAt))
            if let wanted = desired[emoji], wanted != (confirmed[emoji]?.selfReacted ?? false) {
                return (send(emoji), nil)
            }
            clearDesired(emoji)
            return (nil, nil)
        case .failed(let failure):
            clearDesired(emoji)
            return (nil, failure.userError)
        }
    }

    // MARK: - Display

    /// The pills to show, in `ReactionOrdering`; an emoji whose displayed count is 0 has none.
    public var pills: [ReactionPill] {
        let emoji = Set(confirmed.keys).union(desired.keys)
        let pills = emoji.compactMap { emoji -> ReactionPill? in
            let (count, shown) = displayed(emoji)
            guard count > 0 else { return nil }
            return ReactionPill(emoji: emoji, count: UInt64(count), selfReacted: shown, pending: desired[emoji] != nil)
        }
        return ReactionOrdering.sorted(pills)
    }

    /// The emoji the user is shown reacting with, each with when they reacted.
    public var selfReactions: [SelfReaction] {
        Set(confirmed.keys).union(desired.keys).compactMap { emoji in
            guard displayedSelf(emoji) else { return nil }
            let reactedAt = desiredAt[emoji] ?? confirmed[emoji]?.selfReactedAt ?? .distantPast
            return SelfReaction(emoji: emoji, reactedAt: reactedAt)
        }
    }

    // MARK: - Private

    private mutating func accept(_ emoji: String, _ state: Confirmed) {
        if let held = confirmed[emoji], state.version <= held.version { return }
        confirmed[emoji] = state
    }

    private mutating func send(_ emoji: String) -> ReactionCall {
        inFlight.insert(emoji)
        return ReactionCall(op: desired[emoji] == true ? .add : .remove, emoji: emoji)
    }

    private mutating func clearDesired(_ emoji: String) {
        desired[emoji] = nil
        desiredAt[emoji] = nil
    }

    private func displayedSelf(_ emoji: String) -> Bool {
        desired[emoji] ?? confirmed[emoji]?.selfReacted ?? false
    }

    /// The displayed count, signed because an inconsistent confirmed state (self set on a count of
    /// 0) must hide the pill rather than underflow.
    private func displayed(_ emoji: String) -> (count: Int64, shown: Bool) {
        let held = confirmed[emoji]
        let shown = displayedSelf(emoji)
        let base = Int64(clamping: held?.count ?? 0) - (held?.selfReacted == true ? 1 : 0)
        return (base + (shown ? 1 : 0), shown)
    }
}
