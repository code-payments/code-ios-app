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
    /// titles the screen "Chats".
    var isEmbedded: Bool = false

    var body: some View {
        let conversations = conversationController.conversations(of: .tipDm)

        Background(color: .backgroundMain) {
            // v1 keeps its list even when empty — the "Show My Tip Card"
            // button lives in it, so there is no blank state to fill.
            if isEmbedded, conversations.isEmpty {
                NoChatsView()
            } else {
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

                    ForEach(conversations) { conversation in
                        TipConversationRow(conversation: conversation) {
                            router.push(.tipConversation(conversation.id))
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                // The list runs under the bar, so its top edge needs the soft
                // fade rather than the system's default hard cut.
                .softScrollEdge()
            }
        }
        .navigationTitle(isEmbedded ? "Chats" : "Tips")
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            if isEmbedded {
                ToolbarItem(placement: .topBarTrailing) {
                    NewChatButton()
                }
            }
        }
    }
}

// MARK: - NewChatButton -

/// The Chat tab's new-chat affordance, a bar item beside the "Chats" title.
///
/// The title used to be a large flush headline drawn in the content (Android
/// parity — `screenTitleLarge`) with this button laid out next to it, which
/// meant the tab hid its navigation bar. A scroll edge effect is drawn by the
/// bar's background, so without a bar the list met the status bar on a hard
/// line; the standard centred title puts the bar back and lets the list fade
/// under it.
private struct NewChatButton: View {

    @Environment(AppRouter.self) private var router

    var body: some View {
        Button {
            router.push(.usernameLookup)
        } label: {
            // Bar items get their glass from the system on iOS 26, so this
            // carries no button style of its own.
            Image.system(.plus)
                .font(.appTextLarge)
                .foregroundStyle(Color.textMain)
        }
        .accessibilityLabel("New chat")
        .accessibilityIdentifier("new-chat-button")
    }
}

// MARK: - NoChatsView -

/// The v2 Chats tab's empty state, shown until the first tip conversation
/// exists — centred in the space between the navigation bar and the tab bar, so
/// it sits at the same height as the tippable-profile intro on this tab.
private struct NoChatsView: View {

    var body: some View {
        VStack(spacing: 12) {
            Image(.Icons.chatBubbleLarge)
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .foregroundStyle(Color.textMain)

            Text("No Chats Yet")
                .font(.appTextLarge)
                .foregroundStyle(Color.textMain)
                .multilineTextAlignment(.center)

            Text("Start a new chat, or share your profile")
                .font(.appTextSmall)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                // Holds the copy to the design's two-line wrap.
                .frame(maxWidth: 220)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
