//
//  TipConversationsScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// The Tips sheet's root once a profile exists: the Show My Tipcard call to
/// action over the list of tip conversations — tips sent and received.
struct TipConversationsScreen: View {

    @Environment(ConversationController.self) private var conversationController
    @Environment(AppRouter.self) private var router

    var body: some View {
        Background(color: .backgroundMain) {
            List {
                Button("Show My Tipcard") {
                    router.push(.tipcard)
                }
                .buttonStyle(.filled)
                .accessibilityIdentifier("show-my-tipcard-button")
                .listRowInsets(EdgeInsets(top: 16, leading: 20, bottom: 16, trailing: 20))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                ForEach(conversationController.conversations(of: .tipDm)) { conversation in
                    TipConversationRow(conversation: conversation) {
                        router.push(.tipConversation(conversation.id))
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Tips")
        .toolbarTitleDisplayMode(.inline)
    }
}

// MARK: - TipConversationRow -

/// One tip conversation, on the same row scaffold as the Send list: the
/// counterpart's avatar and name, the last-message preview, and the unread
/// state.
private struct TipConversationRow: View {

    let conversation: Conversation
    let onTap: () -> Void

    @Environment(ConversationController.self) private var conversationController
    @Environment(SessionContainer.self) private var sessionContainer
    @Environment(Session.self) private var session

    var body: some View {
        let counterpart = conversation.counterpart(excluding: conversationController.selfUserID)
        let title = conversationController.displayName(for: conversation)
        let subtitle = conversationController.lastMessagePreview(for: conversation) {
            session.balance(for: $0)?.name
        }
        let hasUnread = conversation.hasUnread(for: conversationController.selfUserID)

        RecipientRowScaffold(
            avatarID: counterpart?.userID?.uuidString ?? conversation.id.description,
            title: title,
            subtitle: subtitle,
            imageData: sessionContainer.tipAvatars.data(for: counterpart?.userID),
            accessoryPlacement: .titleLine,
            accessibilityLabel: hasUnread ? "\(title), unread messages" : title,
            onTap: onTap
        ) {
            RecipientRowAccessory(
                timestamp: conversation.lastActivity,
                isUnknown: false,
                hasUnread: hasUnread
            )
        }
        .task(id: counterpart?.userID) {
            await sessionContainer.tipAvatars.load(
                userID: counterpart?.userID,
                picture: counterpart?.profilePicture
            )
        }
    }
}
