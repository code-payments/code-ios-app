//
//  ChatStreamEvent.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI

/// A decoded update delivered over the single per-user event stream. The
/// streamer demultiplexes raw `ChatUpdate`s into these so the controller can
/// apply them without touching proto types. PoC scope omits pointers/typing.
public enum ChatStreamEvent: Sendable {

    /// New messages arrived in a chat.
    case newMessages(chatID: ChatID, messages: [ChatMessage])

    /// A chat's full metadata was refreshed (members/last message/last activity).
    case metadataRefresh(Conversation)

    /// Only a chat's last-activity timestamp changed — re-sort the feed.
    case lastActivityChanged(chatID: ChatID, date: Date)
}

extension ChatStreamEvent {

    /// Decodes a raw stream event into zero or more domain events. Pure and
    /// synchronous so it is unit-testable without the actor or a live stream;
    /// non-chat events (test events, future types) decode to an empty array.
    public static func decode(_ event: Flipcash_Event_V1_Event) -> [ChatStreamEvent] {
        guard case .chatUpdate(let update)? = event.type else { return [] }

        let chatID = ChatID(update.chat)
        var events: [ChatStreamEvent] = []

        let messages = update.newMessages.messages.compactMap(ChatMessage.init)
        if !messages.isEmpty {
            events.append(.newMessages(chatID: chatID, messages: messages))
        }

        for metadataUpdate in update.metadataUpdates {
            switch metadataUpdate.kind {
            case .fullRefresh(let refresh):
                events.append(.metadataRefresh(Conversation(refresh.metadata)))
            case .lastActivityChanged(let changed):
                events.append(.lastActivityChanged(chatID: chatID, date: changed.newLastActivity.date))
            case nil:
                break
            }
        }

        return events
    }
}
