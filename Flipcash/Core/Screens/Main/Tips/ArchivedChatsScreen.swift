//
//  ArchivedChatsScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// Archived chats, on the same row as the main list, newest activity first. A swipe unarchives.
/// Opening a chat from here does not unarchive it (rule 4).
struct ArchivedChatsScreen: View {

    @Environment(ConversationController.self) private var conversationController
    @Environment(AppRouter.self) private var router

    var body: some View {
        let conversations = conversationController.archivedConversations

        Background(color: .backgroundMain) {
            if conversations.isEmpty {
                Text("No archived chats")
                    .font(.appTextMedium)
                    .foregroundStyle(Color.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(Array(conversations.enumerated()), id: \.element.id) { index, conversation in
                        TipConversationRow(conversation: conversation) {
                            router.push(.tipConversation(conversation.id))
                        }
                        .listRowSeparator(index == 0 ? .hidden : .automatic, edges: .top)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button {
                                conversationController.unarchive(conversation.id)
                            } label: {
                                // Swipe actions fill symbols by default; the shared design uses the outline.
                                Image(systemName: "tray.and.arrow.up")
                                    .environment(\.symbolVariants, .none)
                            }
                            .tint(.backgroundRow)
                            .accessibilityLabel("Unarchive chat")
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Archived")
        .toolbarTitleDisplayMode(.inline)
    }
}
