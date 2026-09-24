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

    /// The boundary for a viewer whose stored READ pointer is `readPointer`.
    ///
    /// `firstInbound` answers the oldest stored message after a given id that someone else sent,
    /// deleted or not; `unreadCount` answers how many inbound, non-deleted messages are stored after
    /// it. The resolved read-through sits just below that first inbound message, so the viewer's
    /// own messages after the pointer fall above the divider. Those arise only when a send's pointer
    /// update was lost, and the placement rule alone would find no gap for them. Android resolves it
    /// the same way.
    ///
    /// A missing pointer resolves to `.none`, not to "everything is unread": a group's roster is
    /// paged, so the viewer's own member row can be absent, and treating that as a pointer of zero
    /// would head the whole transcript with the divider. This is deliberately not
    /// ``Conversation/hasUnread(for:)``, which counts a missing pointer as unread.
    ///
    /// `hasStored` answers whether any message at or below a given id is stored. When none is, the
    /// store has a gap below the unread run and can't know how many unread messages precede it, so
    /// the boundary resolves to `.none` rather than a count that may be short.
    public static func resolve(
        readPointer: MessageID?,
        firstInbound: (MessageID) -> MessageID?,
        unreadCount: (MessageID) -> Int,
        hasStored: (MessageID) -> Bool
    ) -> UnreadBoundary {
        guard let readPointer, let first = firstInbound(readPointer) else { return .none }
        let readThrough = MessageID(value: first.value - 1)
        guard hasStored(readThrough) else { return .none }
        let count = unreadCount(readPointer)
        guard count > 0 else { return .none }
        return .at(readThrough: readThrough, count: count)
    }

    /// Whether the divider sits between two adjacent messages, `older` directly above `newer`.
    ///
    /// Compares ranges rather than matching the read-through message's id, so the divider still
    /// lands when that message was deleted or is outside the loaded window. Ids increase down the
    /// transcript, so at most one adjacent pair answers true.
    public func dividerBetween(newer: ConversationMessage, older: ConversationMessage, selfUserID: UserID) -> Bool {
        switch self {
        case .none:
            return false
        case .at(let readThrough, _):
            return older.id <= readThrough && readThrough < newer.id && !newer.isFromSelf(selfUserID)
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
