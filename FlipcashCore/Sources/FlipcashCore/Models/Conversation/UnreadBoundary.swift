//
//  UnreadBoundary.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// Where the viewer's unread messages began when they opened a chat, and how many there were.
///
/// Resolved once per visit, before anything advances the viewer's READ pointer, and never re-read:
/// a message arriving later neither moves the divider nor changes its count. Android implements the
/// same rule (`UnreadBoundary` in the messenger module); both platforms encode one table of cases.
public enum UnreadBoundary: Hashable, Sendable {
    /// No divider: nothing inbound is unread, or the viewer's own READ pointer is unknown.
    case none
    /// The viewer had read through `readThrough`, and `count` inbound messages followed it.
    case at(readThrough: MessageID, count: Int)

    /// The boundary for a viewer whose stored READ pointer is `readPointer`, with `unreadCount`
    /// answering how many inbound, non-deleted messages are stored after a given id.
    ///
    /// A missing pointer resolves to `.none`, not to "everything is unread": a group's roster is
    /// paged, so the viewer's own member row can be absent, and treating that as a pointer of zero
    /// would head the whole transcript with the divider. This is deliberately not
    /// ``Conversation/hasUnread(for:)``, which counts a missing pointer as unread.
    public static func resolve(readPointer: MessageID?, unreadCount: (MessageID) -> Int) -> UnreadBoundary {
        guard let readPointer else { return .none }
        let count = unreadCount(readPointer)
        guard count > 0 else { return .none }
        return .at(readThrough: readPointer, count: count)
    }

    /// The message the divider heads in `messages`, oldest first: the first message after the
    /// read-through that someone else sent.
    ///
    /// Compares ranges rather than matching the read-through message's id, so the divider still
    /// lands when that message was deleted. Skips the viewer's own messages after the pointer, which
    /// arise only when a send's pointer update was lost. Nil when `messages` starts after the
    /// read-through, because the message the divider belongs above may not be loaded.
    public func messageUnderDivider(in messages: [ConversationMessage], selfUserID: UserID) -> ConversationMessage? {
        switch self {
        case .none:
            return nil
        case .at(let readThrough, _):
            guard let oldest = messages.first, oldest.id <= readThrough else { return nil }
            return messages.first { $0.id > readThrough && !$0.isFromSelf(selfUserID) }
        }
    }

    /// The number the divider shows, or nil when there is no divider.
    public var count: Int? {
        switch self {
        case .none: nil
        case .at(_, let count): count
        }
    }
}

/// How long the unread divider stays once the chat is open. Android carries the same seam.
public enum UnreadDividerLifetime: Sendable {
    /// For the whole visit.
    case untilClose
    /// Until the viewer sends a message, which says they have caught up.
    case untilSend

    /// The lifetime the app ships. Switching behaviour is a change to this one constant.
    public static let current: UnreadDividerLifetime = .untilClose
}
