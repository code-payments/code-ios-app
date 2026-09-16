//
//  ConversationStreamEvent.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI

/// A decoded update delivered over the single per-user event stream. The
/// streamer demultiplexes raw `ChatUpdate`s into these so the controller can
/// apply them without touching proto types.
public enum ConversationStreamEvent: Sendable {

    /// Durable, sequenced event-log mutations for a conversation (message sent/edited/deleted). The
    /// store applies them last-writer-wins by `event_sequence` and gap-detects via `sequence`/`count`,
    /// catching up with `GetDelta` on a gap.
    case chatEvents(conversationID: ConversationID, events: [DecodedChatEvent])

    /// A conversation's full metadata was refreshed (members/last message/last activity).
    case metadataRefresh(Conversation)

    /// Only a conversation's last-activity timestamp changed — re-sort the feed.
    case lastActivityChanged(conversationID: ConversationID, date: Date)

    /// One or more members' READ watermarks advanced.
    case readPointersChanged(conversationID: ConversationID, pointers: [MemberReadPointer])

    /// One or more members started or stopped typing. Ephemeral — never persisted or part of the
    /// event log; the controller holds it as transient UI state and the server clears it with a
    /// stopped/timed-out notification.
    case typingChanged(conversationID: ConversationID, notifications: [TypingNotification])

    /// One or more members joined or left the roster. Like `readPointersChanged`, this rides outside
    /// the gap-detected event log as a convergent overlay — the store applies each update by
    /// `RosterSummary.version` (a greater version wins, drop-if-not-greater), so delivery order
    /// doesn't matter.
    case rosterChanged(conversationID: ConversationID, updates: [DecodedRosterUpdate])
}

/// One durable event in a chat's log: a contiguous run of mutations delivered atomically. `sequence`
/// is the END of the half-open range this event occupies; `count` is the number of mutations. Clients
/// apply mutations in ascending `sequence` and gap-detect via `localCursor + count == sequence`.
public struct DecodedChatEvent: Sendable {
    public let sequence: UInt64
    public let count: UInt64
    public let mutations: [DecodedMutation]

    public init(sequence: UInt64, count: UInt64, mutations: [DecodedMutation]) {
        self.sequence = sequence
        self.count = count
        self.mutations = mutations
    }
}

/// A single mutation within an event. Each carries the full materialized message; a delete carries a
/// `.deleted` tombstone. The store applies them uniformly by last-writer-wins.
public enum DecodedMutation: Sendable {
    case sent(ConversationMessage)
    case edited(ConversationMessage)
    case deleted(ConversationMessage)

    /// The materialized message this mutation applies (a send, the edited state, or the tombstone).
    public var message: ConversationMessage {
        switch self {
        case .sent(let message), .edited(let message), .deleted(let message):
            return message
        }
    }
}

/// A member's READ watermark from a live pointer update: everything at or before
/// `value` is read by `userID`. `date` is when they advanced the pointer, for
/// the read receipt; `nil` when the server omits the timestamp.
public struct MemberReadPointer: Sendable, Hashable {
    public let userID: UserID
    public let value: MessageID
    public let date: Date?

    public init(userID: UserID, value: MessageID, date: Date? = nil) {
        self.userID = userID
        self.value = value
        self.date = date
    }
}

/// One live roster change from a `RosterUpdate`: the chat's roster summary after the change (compared
/// by ``ConversationRosterSummary/version`` — apply a greater version, drop the rest) and what
/// changed. Delivered to every member of the chat, including — for a join — the joining member's
/// other devices and — for a leave — the leaving member themself.
public struct DecodedRosterUpdate: Sendable {
    public let rosterSummary: ConversationRosterSummary
    public let change: RosterChange

    public init(rosterSummary: ConversationRosterSummary, change: RosterChange) {
        self.rosterSummary = rosterSummary
        self.change = change
    }
}

/// What changed in a roster update.
public enum RosterChange: Sendable {
    /// A member joined. `chat` is the full chat snapshot, set only when the signed-in user is the
    /// member who joined — the recipient inserts it into their feed directly, without a refetch.
    /// `nil` for every other member's join.
    case joined(member: ConversationMember, chat: Conversation?)
    /// A member left. Naming the signed-in user means the recipient is no longer a member and should
    /// remove the chat from their feed.
    case left(userID: UserID)
}

extension ConversationStreamEvent {

    /// Decodes a raw stream event into zero or more domain events. Pure and
    /// synchronous so it is unit-testable without the actor or a live stream;
    /// non-conversation events (test events, future types) decode to an empty array.
    public static func decode(_ event: Flipcash_Event_V1_Event) -> [ConversationStreamEvent] {
        guard case .chatUpdate(let update)? = event.type else { return [] }

        let conversationID = ConversationID(update.chat)
        var events: [ConversationStreamEvent] = []

        // The sequenced event log (message sent/edited/deleted).
        let chatEvents = update.events.events.map(DecodedChatEvent.init)
        if !chatEvents.isEmpty {
            events.append(.chatEvents(conversationID: conversationID, events: chatEvents))
        }

        for metadataUpdate in update.metadataUpdates {
            switch metadataUpdate.kind {
            case .fullRefresh(let refresh):
                events.append(.metadataRefresh(Conversation(refresh.metadata)))
            case .lastActivityChanged(let changed):
                events.append(.lastActivityChanged(conversationID: conversationID, date: changed.newLastActivity.date))
            case nil:
                break
            }
        }

        let readPointers: [MemberReadPointer] = update.pointerUpdates.pointers.compactMap { pointer in
            switch pointer.type {
            case .read:
                guard let userID = try? UUID(data: pointer.userID.value) else { return nil }
                return MemberReadPointer(userID: userID, value: MessageID(pointer.value), date: pointer.hasTs ? pointer.ts.date : nil)
            case .delivered, .sent, .unknown, .UNRECOGNIZED:
                return nil
            }
        }
        if !readPointers.isEmpty {
            events.append(.readPointersChanged(conversationID: conversationID, pointers: readPointers))
        }

        let typing = update.isTypingNotifications.isTypingNotifications.compactMap(TypingNotification.init)
        if !typing.isEmpty {
            events.append(.typingChanged(conversationID: conversationID, notifications: typing))
        }

        let rosterUpdates = update.rosterUpdates.rosterUpdates.compactMap(DecodedRosterUpdate.init)
        if !rosterUpdates.isEmpty {
            events.append(.rosterChanged(conversationID: conversationID, updates: rosterUpdates))
        }

        return events
    }
}

extension DecodedChatEvent {
    /// Non-failable: an event whose mutations are all unrepresentable (e.g. a media message this client
    /// can't show) still carries a valid `sequence`/`count`, so the cursor must advance past it rather
    /// than gap-loop forever. `count` stays the server's value — the log advanced by it regardless of
    /// what the client can materialize.
    init(_ proto: Flipcash_Messaging_V1_Event) {
        self.init(
            sequence: proto.sequence,
            count: UInt64(proto.count),
            mutations: proto.mutations.compactMap(DecodedMutation.init)
        )
    }
}

extension DecodedMutation {
    /// Nil for a mutation whose message the client can't represent (unknown/media/reply content). A
    /// deleted message materializes as a `.deleted` tombstone via `ConversationMessage.init`.
    init?(_ proto: Flipcash_Messaging_V1_Mutation) {
        switch proto.type {
        case .messageSent(let proto):
            guard let message = ConversationMessage(proto) else { return nil }
            self = .sent(message)
        case .messageEdited(let proto):
            guard let message = ConversationMessage(proto) else { return nil }
            self = .edited(message)
        case .messageDeleted(let proto):
            guard let message = ConversationMessage(proto) else { return nil }
            self = .deleted(message)
        case .none:
            return nil
        }
    }
}

extension DecodedRosterUpdate {
    /// Nil when the update carries no roster summary (nothing to version-compare against) or its kind
    /// is neither joined nor left (a future oneof case this client doesn't know about yet).
    init?(_ proto: Flipcash_Chat_V1_RosterUpdate) {
        guard proto.hasRosterSummary else { return nil }
        let rosterSummary = ConversationRosterSummary(proto.rosterSummary)
        switch proto.kind {
        case .memberJoined(let joined):
            let member = ConversationMember(joined.member)
            let chat = joined.hasMetadata ? Conversation(joined.metadata) : nil
            self.init(rosterSummary: rosterSummary, change: .joined(member: member, chat: chat))
        case .memberLeft(let left):
            guard let userID = try? UUID(data: left.userID.value) else { return nil }
            self.init(rosterSummary: rosterSummary, change: .left(userID: userID))
        case nil:
            return nil
        }
    }
}
