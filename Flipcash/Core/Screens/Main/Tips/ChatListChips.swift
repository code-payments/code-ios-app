//
//  ChatListChips.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// The Chats tab's chip filters. The selection lives in the screen's `@State` and is never
/// persisted: every cold start opens on `.all`.
enum ChatListFilter: Hashable {
    case all
    case unread
    case groups
    case dms

    /// The chips the row shows, in order: Groups outside the group-money UI, DMs under it.
    static func chips(showsGroupMoney: Bool) -> [ChatListFilter] {
        [.all, .unread, showsGroupMoney ? .dms : .groups]
    }

    var title: String {
        switch self {
        case .all: "All"
        case .unread: "Unread"
        case .groups: "Groups"
        case .dms: "DMs"
        }
    }

    func ids<ID>(in projection: ChatListProjection<ID>) -> [ID] {
        switch self {
        case .all: projection.main
        case .unread: projection.unreadChip
        case .groups: projection.groupsChip
        case .dms: projection.dmsChip
        }
    }

    /// The number a chip shows: unread chats inside its filter, or nothing when zero. `All` shows
    /// none because the tab badge already shows that number.
    func badge<ID>(in projection: ChatListProjection<ID>) -> Int? {
        let count: Int = switch self {
        case .all: 0
        case .unread: projection.unreadChipCount
        case .groups: projection.groupsChipCount
        case .dms: projection.dmsChipCount
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
        case .dms: "No DMs"
        }
    }
}

struct ChatListChips: View {

    @Binding var selection: ChatListFilter
    let projection: ChatListProjection<ConversationID>
    let showsGroupMoney: Bool

    var body: some View {
        HStack(spacing: 8) {
            ForEach(ChatListFilter.chips(showsGroupMoney: showsGroupMoney), id: \.self) { filter in
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
        .sensoryFeedback(.selection, trigger: selection)
    }
}
