//
//  ChatItem.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// A single rendered row in the transcript: a message bubble, or a heading such as a centered date
/// header or the unread divider. A heading carries no sender or grouping, so it's a distinct case
/// rather than a message with unused fields. The delivery line rides on its message
/// (`ChatMessage.receipt`), not as its own row. The whole transcript is driven by `[ChatItem]`.
public enum ChatItem: Hashable, Sendable, Codable, Identifiable {
    case message(ChatMessage)
    /// A centered day + time header, e.g. "Today 12:13 PM". `text` is already formatted.
    case dateSeparator(id: String, text: String)
    /// The "N Unread Messages" band above the first message the viewer had not read when they
    /// opened the chat. At most one per transcript.
    case unreadDivider(count: Int)
    /// A leading-aligned typing bubble pinned at the transcript tail while the counterpart types.
    /// In a group, `typists` holds the newest few people typing, oldest first, drawn as avatars
    /// ahead of the bubble; it is empty in a DM, which draws the bubble alone.
    case typingIndicator(typists: [ChatAuthor])
    /// The "Encrypted" line above the first end-to-end-encrypted message in the transcript, or at
    /// its head when every message is encrypted. At most one per transcript.
    case encryptionMarker
    /// A server-authored notice drawn as a leading-aligned line, not a bubble. `text` is the server's
    /// fallback text, shown unmodified. `serverID` is the notice's message id, which the READ pointer
    /// moves past like any inbound message's. `userLink` is the name in `text` that opens a profile.
    case systemMessage(id: String, text: String, serverID: MessageID?, userLink: SystemNoticeUserLink? = nil)
    /// The "Your Group Is Ready" card at the head of a group the viewer is alone in. Client-only: it
    /// is never a message, so nothing stores or syncs it.
    case inviteCard(groupName: String)

    public var isInviteCard: Bool {
        if case .inviteCard = self { true } else { false }
    }

    public var id: String {
        switch self {
        case .message(let message): message.id
        case .dateSeparator(let id, _): id
        case .unreadDivider: "unread-divider"
        // Independent of `typists`, so a typist joining or leaving updates the row in place.
        case .typingIndicator: "typing-indicator"
        case .encryptionMarker: "encryption-marker"
        case .systemMessage(let id, _, _, _): id
        // Independent of `isLeaving`, so the exit reconfigures the row in place.
        case .inviteCard: "invite-card"
        }
    }

    /// The most typists a group's typing indicator draws; the newest win.
    public static let maxTypingAvatars = 3

    /// The id of the message this row draws some or all of, or nil for a row that is not a message.
    /// A message split around its link card spans several rows that all answer the same here.
    public var messageID: String? {
        switch self {
        case .message(let message): message.messageID
        case .dateSeparator, .unreadDivider, .typingIndicator, .encryptionMarker, .systemMessage, .inviteCard: nil
        }
    }

    /// The unread divider's label: "1 Unread Message", "12 Unread Messages", and "99+ Unread
    /// Messages" past 99, as Android shows it.
    public static func unreadDividerText(count: Int) -> String {
        switch count {
        case 1: "1 Unread Message"
        default: "\(UnreadCountLabel.text(for: count)) Unread Messages"
        }
    }
}
