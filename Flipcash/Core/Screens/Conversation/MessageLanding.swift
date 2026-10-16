//
//  MessageLanding.swift
//  Flipcash
//

import FlipcashCore

/// Where a message link opens a chat: the message to land on, and the chat the link was tapped in,
/// which the transcript offers a way back to.
nonisolated struct MessageLanding: Hashable, Sendable {
    /// The linked message, by its per-chat id.
    let messageID: MessageID
    /// The chat the link was tapped in, or nil when it came from outside a chat.
    let returnTo: ConversationID?
    /// Whether the landed chat was pushed over `returnTo`'s screen, so going back pops to that
    /// screen as the reader left it rather than reopening it at the bottom.
    var isOverReturnChat = false
}

/// One request to scroll the transcript to a message and flash it. `token` makes a repeat jump to
/// the same message a new request.
struct MessageJump: Equatable {
    /// The row's stable id: the message id's value as a string.
    let stableID: String
    let token: Int
}
