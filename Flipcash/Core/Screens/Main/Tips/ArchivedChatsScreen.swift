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
    @Environment(\.colorScheme) private var colorScheme

    @State private var muteTarget: ArchivedMuteTarget?

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
                                SwipeActionLabel(title: "Unarchive", icon: .arrowInbox)
                            }
                            .tint(.backgroundRow)
                            .accessibilityLabel("Unarchive chat")
                        }
                        .chatRowActions(
                            for: conversation,
                            in: .archived,
                            isEnabled: true,
                            onMute: { muteTarget = ArchivedMuteTarget(id: conversation.id) },
                            onArchive: { conversationController.unarchive(conversation.id) },
                            onSelect: nil
                        )
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Archived")
        .toolbarTitleDisplayMode(.inline)
        // The stream follows archived groups while this screen is up, so its rows stay current.
        .onAppear { conversationController.isArchiveScreenVisible = true }
        .onDisappear { conversationController.isArchiveScreenVisible = false }
        .tray(item: $muteTarget) { target in
            MuteChatSheet(
                conversationID: target.id,
                isPresented: Binding(get: { muteTarget != nil }, set: { if !$0 { muteTarget = nil } })
            )
        }
    }
}

/// The archived chat whose mute sheet the long-press menu opened.
private struct ArchivedMuteTarget: Identifiable {
    let id: ConversationID
}
