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

    /// New messages arrived in a conversation.
    case newMessages(conversationID: ConversationID, messages: [ConversationMessage])

    /// Durable, sequenced event-log mutations for a conversation (message sent/edited/deleted). The
    /// store applies them last-writer-wins by `event_sequence` and gap-detects via `sequence`/`count`,
    /// catching up with `GetDelta` on a gap. Supersedes the deprecated `newMessages` overlay.
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

extension ConversationStreamEvent {

    /// Decodes a raw stream event into zero or more domain events. Pure and
    /// synchronous so it is unit-testable without the actor or a live stream;
    /// non-conversation events (test events, future types) decode to an empty array.
    public static func decode(_ event: Flipcash_Event_V1_Event) -> [ConversationStreamEvent] {
        guard case .chatUpdate(let update)? = event.type else { return [] }

        let conversationID = ConversationID(update.chat)
        var events: [ConversationStreamEvent] = []

        // The sequenced event log (message sent/edited/deleted). Additive with `new_messages`: both may
        // carry the same send during the server's migration window, and last-writer-wins by
        // `event_sequence` in the store lands it exactly once.
        let chatEvents = update.events.events.map(DecodedChatEvent.init)
        if !chatEvents.isEmpty {
            events.append(.chatEvents(conversationID: conversationID, events: chatEvents))
        }

        // The deprecated real-time overlay. Decoded regardless of `events` so a message that arrives
        // only here (an events-empty or malformed batch) is never dropped; the store dedups by version.
        let messages = update.newMessages.messages.compactMap(ConversationMessage.init)
        if !messages.isEmpty {
            events.append(.newMessages(conversationID: conversationID, messages: messages))
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
