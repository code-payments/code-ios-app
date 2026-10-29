//
//  ReactionAlert.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import CoreGraphics

/// The rules that decide whether a reaction update raises an in-app alert.
///
/// Mirrors `docs/specs/in-app-reaction-alerts.md` in the orchestrator repo: an alert shows for an
/// add or a boost, by someone else, on a message the user sent, while the app is in front. Every
/// rule is a pure function so each has a test; the controller that owns the clock, the database and
/// the pill only feeds them values.
public enum ReactionAlertTrigger {

    /// Why an update raises no alert.
    public enum Drop: Hashable, Sendable {
        case background
        case ownActor
        case removed
        case notOwnMessage
        /// The sender could not be established from the local copy or from the server.
        case senderUnknown
    }

    /// The rules that need nothing but the update, checked before the message's sender is looked up.
    /// Nil means the update may still qualify.
    public static func precheck(_ update: DecodedReactionUpdate, selfUserID: UserID, isForeground: Bool) -> Drop? {
        guard isForeground else { return .background }
        guard update.actor != selfUserID else { return .ownActor }
        guard update.added else { return .removed }
        return nil
    }

    /// The sender rule: the message must be the user's own. A nil sender means the lookup failed.
    public static func checkSender(_ sender: UserID?, selfUserID: UserID) -> Drop? {
        guard let sender else { return .senderUnknown }
        return sender == selfUserID ? nil : .notOwnMessage
    }

    /// The amount one boost added, in USD cents.
    ///
    /// `actor_boost_usd` is the actor's new total on the emoji, so the amount is the rise over the
    /// total last seen for that actor. With no earlier total, or one not below the new total (a
    /// stale or reordered update), the new total is shown instead.
    public static func boostDeltaCents(newTotalCents: UInt64, previousCents: UInt64?) -> UInt64 {
        guard let previousCents, previousCents < newTotalCents else { return newTotalCents }
        return newTotalCents - previousCents
    }
}

/// The last boost total seen per actor and emoji on a message.
///
/// A stored message keeps only the viewer's own boost total (`ReactionState.Confirmed.selfBoostCents`),
/// so the other actors' totals are tracked here, in memory. After a relaunch a boost shows its full
/// total, which the spec allows when the previous total is unknown.
public struct ActorBoostTracker: Sendable {

    private struct Key: Hashable, Sendable {
        let messageID: MessageID
        let actor: UserID
        let emoji: String
    }

    private var totals: [Key: UInt64] = [:]

    public init() {}

    /// Records `newTotalCents` as the actor's total on the update's emoji and returns the amount the
    /// boost added. Call it for every boosted update, qualifying or not, so the next one has its
    /// predecessor.
    public mutating func recordBoost(_ update: DecodedReactionUpdate, newTotalCents: UInt64) -> UInt64 {
        let key = Key(messageID: update.messageID, actor: update.actor, emoji: update.emoji)
        let delta = ReactionAlertTrigger.boostDeltaCents(newTotalCents: newTotalCents, previousCents: totals[key])
        totals[key] = max(newTotalCents, totals[key] ?? 0)
        return delta
    }
}

/// Where an alert for a message goes, given what the user is looking at.
public enum ReactionAlertPlacement: Hashable, Sendable {

    /// What the pill's top row reads.
    public enum TopRow: Hashable, Sendable {
        /// Any other screen: the chat's name.
        case chatName
    }

    /// The message is in the open chat: its bubble's own animation covers it, and an off-screen
    /// reaction waits in the transcript. No pill.
    case bubbleOnly
    case pill(TopRow)

    public static func decide(
        alertConversation: ConversationID,
        openConversation: ConversationID?
    ) -> ReactionAlertPlacement {
        alertConversation == openConversation ? .bubbleOnly : .pill(.chatName)
    }
}

/// One qualifying reaction or boost, ready to show.
public struct ReactionAlertEvent: Hashable, Sendable {
    public let conversationID: ConversationID
    public let messageID: MessageID
    public let emoji: String
    public let actor: UserID
    public let actorName: String
    public let isBoost: Bool
    /// What a boost added, in USD cents; 0 for a plain reaction.
    public let boostDeltaCents: UInt64
    /// The quoted message text.
    public let snippet: String
    /// The top row: the chat's name.
    public let topRow: String

    public init(
        conversationID: ConversationID,
        messageID: MessageID,
        emoji: String,
        actor: UserID,
        actorName: String,
        isBoost: Bool,
        boostDeltaCents: UInt64 = 0,
        snippet: String,
        topRow: String
    ) {
        self.conversationID = conversationID
        self.messageID = messageID
        self.emoji = emoji
        self.actor = actor
        self.actorName = actorName
        self.isBoost = isBoost
        self.boostDeltaCents = boostDeltaCents
        self.snippet = snippet
        self.topRow = topRow
    }
}

/// What one pill shows: the events on one message that landed within a hold.
public struct ReactionAlertPill: Hashable, Sendable {
    public let conversationID: ConversationID
    public let messageID: MessageID
    public private(set) var events: [ReactionAlertEvent]

    init(_ event: ReactionAlertEvent) {
        conversationID = event.conversationID
        messageID = event.messageID
        events = [event]
    }

    /// Folds `event` in. The same actor and emoji replaces its earlier entry, so a repeated boost
    /// swaps in place rather than listing twice; anything else is appended.
    mutating func merge(_ event: ReactionAlertEvent) {
        if let index = events.firstIndex(where: { $0.actor == event.actor && $0.emoji == event.emoji }) {
            events.remove(at: index)
        }
        events.append(event)
    }

    /// Each actor once, by their first event.
    public var actors: [ReactionAlertEvent] {
        var seen = Set<UserID>()
        return events.filter { seen.insert($0.actor).inserted }
    }

    public var latest: ReactionAlertEvent { events[events.count - 1] }

    /// Two or more actors on the same message.
    public var isStacked: Bool { actors.count > 1 }

    /// How long the pill holds open: longer for a boost.
    public var hold: Duration { latest.isBoost && !isStacked ? .milliseconds(3500) : .milliseconds(2500) }

    public var topRow: String { latest.topRow }

    public var title: String {
        guard isStacked else {
            let event = latest
            return event.isBoost
                ? "\(event.actorName) boosted their \(event.emoji)"
                : "\(event.actorName) reacted to your message"
        }
        let others = actors.count - 1
        return "\(actors[0].actorName) and \(others) \(others == 1 ? "other" : "others") reacted"
    }

    public var subtitle: String { latest.snippet }

    /// The emoji a stacked pill lists: distinct, newest last, at most three.
    public var emojis: [String] {
        var distinct: [String] = []
        for event in events where !distinct.contains(event.emoji) { distinct.append(event.emoji) }
        return Array(distinct.suffix(3))
    }

    /// The boost amount a single-actor boost pill shows, in USD cents; nil otherwise.
    public var boostCents: UInt64? {
        guard !isStacked, latest.isBoost else { return nil }
        return latest.boostDeltaCents
    }
}

/// One pill at a time. Events for the pill's own message merge into it; events for another message
/// wait their turn.
public struct ReactionAlertQueue: Sendable {

    public enum Outcome: Hashable, Sendable {
        /// Nothing was showing; the event is now the pill.
        case started
        /// Folded into the pill on screen, which restarts its hold.
        case merged
        /// Held until the pill on screen closes.
        case queued
    }

    public private(set) var current: ReactionAlertPill?
    public private(set) var waiting: [ReactionAlertPill] = []

    public init() {}

    @discardableResult
    public mutating func enqueue(_ event: ReactionAlertEvent) -> Outcome {
        guard current != nil else {
            current = ReactionAlertPill(event)
            return .started
        }
        if current?.conversationID == event.conversationID, current?.messageID == event.messageID {
            current?.merge(event)
            return .merged
        }
        if let index = waiting.firstIndex(where: { $0.conversationID == event.conversationID && $0.messageID == event.messageID }) {
            waiting[index].merge(event)
        } else {
            waiting.append(ReactionAlertPill(event))
        }
        return .queued
    }

    /// Closes the pill on screen and promotes the next, returning it.
    @discardableResult
    public mutating func advance() -> ReactionAlertPill? {
        current = waiting.isEmpty ? nil : waiting.removeFirst()
        return current
    }

    /// Drops the pills waiting for a chat, for that chat being opened. The pill on screen is left to
    /// the caller to close, which promotes the next one.
    public mutating func removeWaiting(for conversationID: ConversationID) {
        waiting.removeAll { $0.conversationID == conversationID }
    }

    /// Drops everything, for a sign-out or a trip to the background.
    public mutating func removeAll() {
        current = nil
        waiting.removeAll()
    }
}

/// Where the Dynamic Island sits, from the top safe area, because Apple publishes no API for it.
///
/// Each row is keyed by the top safe-area inset the device reports. Rows marked measured were read
/// off a simulator screenshot; the others are from the published device specs and unverified.
public enum IslandGeometry {

    public struct Row: Equatable, Sendable {
        public let safeAreaTop: CGFloat
        /// The island's top edge, in points from the top of the screen.
        public let top: CGFloat
        public let size: CGSize
        public let isMeasured: Bool
        public let devices: String
    }

    public static let rows: [Row] = [
        Row(safeAreaTop: 59, top: 11, size: CGSize(width: 126, height: 37), isMeasured: false,
            devices: "iPhone 14 Pro, 14 Pro Max, 15, 15 Plus, 15 Pro, 15 Pro Max, 16, 16 Plus"),
        Row(safeAreaTop: 62, top: 11, size: CGSize(width: 126, height: 37), isMeasured: false,
            devices: "iPhone 16 Pro, 16 Pro Max, 17, 17 Pro, 17 Pro Max"),
    ]

    /// The smallest top safe area that belongs to an island phone; notch phones top out at 50.
    public static let minimumSafeAreaTop: CGFloat = 54

    /// The island's frame in screen coordinates, or nil when the device has none and the alert
    /// should drop in as a banner. An inset with no row falls back to the nearest row below it,
    /// and is unverified.
    public static func island(safeAreaTop: CGFloat, screenWidth: CGFloat) -> CGRect? {
        guard safeAreaTop >= minimumSafeAreaTop else { return nil }
        let row = rows.last { $0.safeAreaTop <= safeAreaTop } ?? rows[0]
        return CGRect(x: (screenWidth - row.size.width) / 2, y: row.top, width: row.size.width, height: row.size.height)
    }
}
