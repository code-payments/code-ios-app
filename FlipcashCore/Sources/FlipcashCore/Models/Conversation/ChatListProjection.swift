//
//  ChatListProjection.swift
//  FlipcashCore
//

import Foundation

/// A chat's unread state as the list rules see it. `unknown` is a chat the viewer's read watermark
/// cannot yet size; it counts as unread, matching `Conversation.hasUnread`.
public enum ChatListUnread: Equatable, Sendable {
    case count(Int)
    case unknown

    public var isUnread: Bool {
        if case .count(0) = self { return false }
        return true
    }
}

/// The few facts of a chat the list rules need, decoupled from `Conversation` so the cross-platform
/// fixture can drive them directly. The controller maps a `Conversation` onto this.
public struct ChatListEntry<ID: Hashable & Sendable>: Sendable {
    public let id: ID
    public let type: ConversationType
    public let lastActivity: Date
    public let isArchived: Bool
    public let isMuted: Bool
    public let isHidden: Bool
    public let unread: ChatListUnread

    public init(
        id: ID,
        type: ConversationType,
        lastActivity: Date,
        isArchived: Bool,
        isMuted: Bool,
        isHidden: Bool,
        unread: ChatListUnread
    ) {
        self.id = id
        self.type = type
        self.lastActivity = lastActivity
        self.isArchived = isArchived
        self.isMuted = isMuted
        self.isHidden = isHidden
        self.unread = unread
    }
}

/// Rule 1 and the list section of the spec: what the main list, each chip, the Archived row and the
/// tab badge hold. One function feeds all of them so they cannot disagree.
public struct ChatListProjection<ID: Hashable & Sendable>: Sendable {

    /// Not archived, not hidden, newest activity first. The Chats tab's rows.
    public let main: [ID]
    /// `main` filtered to unread.
    public let unreadChip: [ID]
    /// `main` filtered to groups. Counts toward the chip only when unread; see `groupsChipCount`.
    public let groupsChip: [ID]
    /// Archived and not hidden, newest activity first.
    public let archived: [ID]
    /// Unread chats inside `unreadChip`.
    public let unreadChipCount: Int
    /// Unread groups inside `groupsChip`.
    public let groupsChipCount: Int
    /// An archived chat exists to show.
    public let archivedRowVisible: Bool
    /// Unread, non-muted, non-hidden archived chats, drawn in the secondary colour.
    public let archivedRowCount: Int
    /// Unread chats in `main`, muted included, as the tab badge has always counted.
    public let tabBadge: Int

    public static func project(_ entries: [ChatListEntry<ID>]) -> ChatListProjection {
        // Index breaks ties so equal timestamps keep input order on every run.
        func ordered(_ chats: [ChatListEntry<ID>]) -> [ChatListEntry<ID>] {
            chats.enumerated()
                .sorted { l, r in
                    l.element.lastActivity != r.element.lastActivity
                        ? l.element.lastActivity > r.element.lastActivity
                        : l.offset < r.offset
                }
                .map(\.element)
        }

        let visible = entries.filter { !$0.isHidden }
        let main = ordered(visible.filter { !$0.isArchived })
        let archived = ordered(visible.filter(\.isArchived))
        let unread = main.filter { $0.unread.isUnread }
        let groups = main.filter { $0.type == .group }

        return ChatListProjection(
            main: main.map(\.id),
            unreadChip: unread.map(\.id),
            groupsChip: groups.map(\.id),
            archived: archived.map(\.id),
            unreadChipCount: unread.count,
            groupsChipCount: groups.count { $0.unread.isUnread },
            archivedRowVisible: !archived.isEmpty,
            archivedRowCount: archived.count { $0.unread.isUnread && !$0.isMuted },
            tabBadge: unread.count
        )
    }
}
