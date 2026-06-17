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
/// apply them without touching proto types. Typing notifications are not consumed.
public enum ConversationStreamEvent: Sendable {

    /// New messages arrived in a conversation.
    case newMessages(conversationID: ConversationID, messages: [ConversationMessage])

    /// A conversation's full metadata was refreshed (members/last message/last activity).
    case metadataRefresh(Conversation)

    /// Only a conversation's last-activity timestamp changed — re-sort the feed.
    case lastActivityChanged(conversationID: ConversationID, date: Date)

    /// One or more members' READ watermarks advanced.
    case readPointersChanged(conversationID: ConversationID, pointers: [MemberReadPointer])
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

        return events
    }
}
