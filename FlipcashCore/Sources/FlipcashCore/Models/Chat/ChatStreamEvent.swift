//
//  ChatStreamEvent.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

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
