//
//  ChatItem.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// A single rendered row in the transcript: a message bubble or a centered date header. A
/// separator carries no sender or grouping, so it's a distinct case rather than a message with
/// unused fields. The delivery line rides on its message (`ChatMessage.receipt`), not as its own
/// row. The whole transcript is driven by `[ChatItem]`.
public enum ChatItem: Hashable, Sendable, Codable, Identifiable {
    case message(ChatMessage)
    /// A centered day + time header, e.g. "Today 12:13 PM". `text` is already formatted.
    case dateSeparator(id: String, text: String)
    /// A leading-aligned typing bubble pinned at the transcript tail while the counterpart types.
    case typingIndicator
    /// The counterpart's profile card at the head of a short transcript.
    case profileCard(ChatProfileCard)

    public var id: String {
        switch self {
        case .message(let message): message.id
        case .dateSeparator(let id, _): id
        case .typingIndicator: "typing-indicator"
        case .profileCard: "profile-card"
        }
    }
}
