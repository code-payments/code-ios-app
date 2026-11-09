//
//  ChatListFilter.swift
//  FlipcashCore
//

import Foundation

/// The Chats tab's chip filters. Never persisted: every cold start opens on `.all`. The raw value is
/// the name the shared behavior files use.
public enum ChatListFilter: String, CaseIterable, Hashable, Sendable {
    case all = "All"
    case unread = "Unread"
    case groups = "Groups"

    /// The chats this filter shows, in the projection's order.
    public func ids<ID>(in projection: ChatListProjection<ID>) -> [ID] {
        switch self {
        case .all: projection.main
        case .unread: projection.unreadChip
        case .groups: projection.groupsChip
        }
    }

    /// The number a chip shows: unread chats inside its filter, or nothing when zero. `All` shows
    /// none because the tab badge already shows that number.
    public func badge<ID>(in projection: ChatListProjection<ID>) -> Int? {
        let count: Int = switch self {
        case .all: 0
        case .unread: projection.unreadChipCount
        case .groups: projection.groupsChipCount
        }
        return count > 0 ? count : nil
    }
}
