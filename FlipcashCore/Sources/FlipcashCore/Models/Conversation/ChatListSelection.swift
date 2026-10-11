//
//  ChatListSelection.swift
//  FlipcashCore
//

import Foundation

/// Which conversations the Chats tab lists. The app and the Share Extension both call it, so the
/// extension's picker cannot drift from the tab.
public enum ChatListSelection {

    /// The Chats tab's source rows before archive is applied: tip DMs, then groups the user has
    /// joined, without hidden conversations. Contact DMs and groups reached by link but not joined
    /// never appear.
    public static func source(
        from conversations: [Conversation],
        isMember: (Conversation) -> Bool
    ) -> [Conversation] {
        let visible = conversations.filter { !$0.isHidden }
        return visible.filter { $0.type == .tipDm }
            + visible.filter { $0.type == .group && isMember($0) }
    }

    /// The Chats tab's main list: ``source(from:isMember:)`` minus archived chats, newest activity first.
    public static func mainList(
        from conversations: [Conversation],
        joinedGroupIDs: Set<ConversationID>,
        archivedIDs: Set<ConversationID>
    ) -> [Conversation] {
        let rows = source(from: conversations, isMember: { joinedGroupIDs.contains($0.id) })
        let entries = rows.map { conversation in
            ChatListEntry(
                id: conversation.id,
                type: conversation.type,
                lastActivity: conversation.lastActivity,
                isArchived: archivedIDs.contains(conversation.id),
                isMuted: false,
                isHidden: conversation.isHidden,
                unread: .count(0)
            )
        }
        let byID = Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ChatListProjection.project(entries).main.compactMap { byID[$0] }
    }
}
