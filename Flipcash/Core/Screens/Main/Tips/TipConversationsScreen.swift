//
//  TipConversationsScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// The Chats tab: the list of tip conversations — tips sent and received.
struct TipConversationsScreen: View {

    @Environment(ConversationController.self) private var conversationController
    @Environment(SessionContainer.self) private var sessionContainer
    @Environment(AppRouter.self) private var router

    /// The rows the tab lists, newest activity first. Groups sit among the tip DMs, but only the
    /// ones the user has joined: a group reached by a `/chat/{id}` link and not joined is in the
    /// store so its own screen can offer the join, not so it can appear in a list the user never
    /// added it to.
    private var conversations: [Conversation] {
        let tipDMs = conversationController.conversations(of: .tipDm)
        return (tipDMs + conversationController.joinedGroups)
            .sorted { $0.lastActivity > $1.lastActivity }
    }

    var body: some View {
        let conversations = self.conversations

        Background(color: .backgroundMain) {
            if conversations.isEmpty {
                // Blank until the feed is known, so a cold launch onto this tab doesn't flash "No
                // Chats Yet" in the moment before the cache hydrates.
                if conversationController.hasResolvedFeed {
                    NoChatsView()
                }
            } else {
                List {
                    ForEach(Array(conversations.enumerated()), id: \.element.id) { index, conversation in
                        TipConversationRow(conversation: conversation) {
                            router.push(.tipConversation(conversation.id))
                        }
                        // Separators divide rows from each other; the first
                        // row's leading one just draws a line under the bar.
                        .listRowSeparator(index == 0 ? .hidden : .automatic, edges: .top)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Chats")
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NewChatButton()
            }
        }
        // Takes a finished cache read before the first frame, instead of drawing empty until launch
        // work lets the controller's own hydration run.
        .onAppear {
            conversationController.hydrateIfReady()
        }
        // Every counterpart, not just the rows on screen. A row's own `.task` fires when the row is
        // built, which in a `List` is when it scrolls into view — so without this the avatar below
        // the fold starts downloading at the moment the user is looking at its blurhash.
        .task(id: conversations.count) {
            let selfUserID = conversationController.selfUserID
            let subjects: [(subject: ProfileAvatarStore.AvatarSubject, picture: ProfilePicture?)] =
                conversations.map { conversation in
                    // A group's row draws the chat's own picture, so that is what gets warmed;
                    // `counterpart(excluding:)` would pick an arbitrary member of it.
                    guard conversation.type != .group,
                          let userID = conversation.counterpart(excluding: selfUserID)?.userID
                    else { return (.chat(conversation.id), conversation.picture) }
                    return (
                        .user(userID),
                        conversation.counterpart(excluding: selfUserID)?.profilePicture
                    )
                }
            sessionContainer.profileAvatars.preload(subjects)
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
            router.push(.newChat)
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

/// The Chats tab's empty state, shown until the first tip conversation
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

    /// What the row's avatar is of: the chat itself for a group, whose roster subset has no single
    /// face to stand for it, and the counterpart for a DM.
    private var avatarSubject: ProfileAvatarStore.AvatarSubject {
        guard conversation.type != .group,
              let userID = conversation.counterpart(excluding: conversationController.selfUserID)?.userID
        else { return .chat(conversation.id) }
        return .user(userID)
    }

    /// The picture the ``avatarSubject`` is fetched from.
    private var avatarPicture: ProfilePicture? {
        conversation.type == .group
            ? conversation.picture
            : conversation.counterpart(excluding: conversationController.selfUserID)?.profilePicture
    }

    var body: some View {
        let counterpart = conversation.counterpart(excluding: conversationController.selfUserID)
        let title = conversationController.displayName(for: conversation)
        let subtitle = self.subtitle
        let hasUnread = conversation.hasUnread(for: conversationController.selfUserID)
        // Read once, for the label only — the bell keeps its own clock. A label can't: VoiceOver
        // reads it when it lands on the row, and this view redraws on store changes rather than at
        // the instant a timed mute lapses, so it can be a moment stale.
        let isMuted = conversation.isMuted(at: .now)

        RecipientRowScaffold(
            avatarID: conversation.type == .group
                ? conversation.id.description
                : (counterpart?.userID?.uuidString ?? conversation.id.description),
            title: title,
            subtitle: subtitle,
            imageData: sessionContainer.profileAvatars.data(for: avatarSubject),
            blurhash: avatarPicture?.thumbnailBlurhash,
            accessoryPlacement: .titleLine,
            mute: conversation.viewerState?.mute,
            accessibilityLabel: accessibilityLabel(title: title, hasUnread: hasUnread, isMuted: isMuted),
            onTap: onTap
        ) {
            RecipientRowAccessory(
                timestamp: conversation.lastActivity,
                isUnknown: false,
                hasUnread: hasUnread
            )
        }
        .task(id: avatarSubject) {
            await sessionContainer.profileAvatars.load(avatarSubject, picture: avatarPicture)
        }
    }

    /// The preview line: the last message, or an italic "Nothing yet" for a chat with no message
    /// at all. A group is created empty, and a blank line there reads as a row still loading.
    /// Only a chat that never had a message gets the placeholder — a last message the preview
    /// declines to quote (a tombstone, an empty body) is not nothing, so it leaves the line off.
    private var subtitle: AttributedString? {
        if let preview = conversationController.lastMessagePreview(for: conversation, currencyName: {
            session.balance(for: $0)?.name
        }) {
            return AttributedString(preview)
        }
        guard conversation.lastMessage == nil else { return nil }
        var placeholder = AttributedString("Nothing yet")
        placeholder.inlinePresentationIntent = .emphasized
        return placeholder
    }

    /// The row reads as one element, so the bell's own label is discarded — it has to be said here.
    private func accessibilityLabel(title: String, hasUnread: Bool, isMuted: Bool) -> String {
        [title, hasUnread ? "unread messages" : nil, isMuted ? "muted" : nil]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}
