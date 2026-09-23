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
    /// In a group, `typists` holds the newest few people typing, oldest first, drawn as avatars
    /// ahead of the bubble; it is empty in a DM, which draws the bubble alone.
    case typingIndicator(typists: [ChatAuthor])
    /// The counterpart's profile card at the head of a short transcript.
    case profileCard(ChatProfileCard)
    /// The group's own card at the head of a short group transcript — picture, title, and the
    /// rule the chat runs on.
    case groupCard(ChatGroupCard)

    public var id: String {
        switch self {
        case .message(let message): message.id
        case .dateSeparator(let id, _): id
        // Independent of `typists`, so a typist joining or leaving updates the row in place.
        case .typingIndicator: "typing-indicator"
        case .profileCard: "profile-card"
        case .groupCard: "group-card"
        }
    }

    /// The most typists a group's typing indicator draws; the newest win.
    public static let maxTypingAvatars = 10

    /// The id of the message this row draws some or all of, or nil for a row that is not a message.
    /// A message split around its link card spans several rows that all answer the same here.
    public var messageID: String? {
        switch self {
        case .message(let message): message.messageID
        case .dateSeparator, .typingIndicator, .profileCard, .groupCard: nil
        }
    }
}
