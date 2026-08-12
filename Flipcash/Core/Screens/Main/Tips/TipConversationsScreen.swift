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

    /// See ``TipsScreen/isEmbedded`` — v2 drops the inline tip-card button and
    /// leads with the large "Chats" title.
    var isEmbedded: Bool = false

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(alignment: .leading, spacing: 0) {
                if isEmbedded {
                    ChatsTabTitle()
                }

                List {
                    // v1 only — v2 reaches the tip card from its own tab.
                    if !isEmbedded {
                        Button("Show My Tip Card") {
                            router.push(.tipcard)
                        }
                        .buttonStyle(.filled)
                        .accessibilityIdentifier("show-my-tipcard-button")
                        .listRowInsets(EdgeInsets(top: 16, leading: 20, bottom: 16, trailing: 20))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }

                    ForEach(conversationController.conversations(of: .tipDm)) { conversation in
                        TipConversationRow(conversation: conversation) {
                            router.push(.tipConversation(conversation.id))
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle(isEmbedded ? "" : "Tips")
        .toolbar(isEmbedded ? .hidden : .automatic, for: .navigationBar)
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
            blurhash: counterpart?.profilePicture?.thumbnailBlurhash,
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
