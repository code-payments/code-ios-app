//
//  ChatListChips.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// The Chats tab's chip filters. The selection lives in the screen's `@State` and is never
/// persisted: every cold start opens on `.all`.
enum ChatListFilter: CaseIterable, Hashable {
    case all
    case unread
    case groups

    var title: String {
        switch self {
        case .all: "All"
        case .unread: "Unread"
        case .groups: "Groups"
        }
    }

    func ids<ID>(in projection: ChatListProjection<ID>) -> [ID] {
        switch self {
        case .all: projection.main
        case .unread: projection.unreadChip
        case .groups: projection.groupsChip
        }
    }

    /// The number a chip shows: unread chats inside its filter, or nothing when zero. `All` shows
    /// none because the tab badge already shows that number.
    func badge<ID>(in projection: ChatListProjection<ID>) -> Int? {
        let count: Int = switch self {
        case .all: 0
        case .unread: projection.unreadChipCount
        case .groups: projection.groupsChipCount
        }
        return count > 0 ? count : nil
    }

    /// The one-line empty state for a filter with no chats. `.all` only reaches this when every
    /// chat is archived.
    var emptyMessage: String {
        switch self {
        case .all: "All your chats are archived"
        case .unread: "No unread chats"
        case .groups: "No groups"
        }
    }
}

struct ChatListChips: View {

    @Binding var selection: ChatListFilter
    let projection: ChatListProjection<ConversationID>

    var body: some View {
        HStack(spacing: 8) {
            ForEach(ChatListFilter.allCases, id: \.self) { filter in
                Button {
                    selection = filter
                } label: {
                    HStack(spacing: 4) {
                        Text(filter.title)
                        if let count = filter.badge(in: projection) {
                            Text("\(count)")
                        }
                    }
                }
                .buttonStyle(.selectableChip(isSelected: selection == filter))
                .accessibilityAddTraits(selection == filter ? .isSelected : [])
                .accessibilityIdentifier("chat-filter-\(filter.title.lowercased())")
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }
}
