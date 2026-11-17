//
//  ChatListChips.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// What each chip reads on screen.
extension ChatListFilter {

    var title: String {
        switch self {
        case .all: "All"
        case .unread: "Unread"
        case .groups: "Groups"
        }
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
        .sensoryFeedback(.selection, trigger: selection)
    }
}
