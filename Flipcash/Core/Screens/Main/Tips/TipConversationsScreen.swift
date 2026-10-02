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

    @State private var muteTarget: MuteTarget?
    @State private var filter: ChatListFilter = .all
    /// Set by a pull-down overscroll, cleared by scrolling up. The row is also visible whenever
    /// `filter != .all`, so it never disappears while it is explaining the list.
    @State private var chipsPulledDown = false
    @State private var undoTarget: ConversationID?

    /// The projection once per body pass: rows, chips, the Archived row and the badge agree.
    private var projection: ChatListProjection<ConversationID> {
        conversationController.chatListProjection
    }

    /// Rows for the selected filter, in the projection's order.
    private func rows(_ projection: ChatListProjection<ConversationID>) -> [Conversation] {
        let byID = Dictionary(
            conversationController.chatListConversations.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return filter.ids(in: projection).compactMap { byID[$0] }
    }

    private var chipsVisible: Bool { filter != .all || chipsPulledDown }

    var body: some View {
        let projection = self.projection
        let conversations = rows(projection)
        let nothingAtAll = projection.main.isEmpty && !projection.archivedRowVisible

        Background(color: .backgroundMain) {
            if nothingAtAll {
                // Blank until the feed is known, so a cold launch onto this tab doesn't flash "No
                // Chats Yet" in the moment before the cache hydrates.
                if conversationController.hasResolvedFeed {
                    NoChatsView()
                }
            } else {
                VStack(spacing: 0) {
                    // Above the List, not in it: there is no initial scroll offset to set after the
                    // first frame, so there is nothing to flash. Height is 0 or natural.
                    if chipsVisible {
                        ChatListChips(selection: $filter, projection: projection)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    List {
                        if projection.archivedRowVisible {
                            ArchivedRow(count: projection.archivedRowCount) {
                                router.push(.archivedChats)
                            }
                            .listRowSeparator(.hidden, edges: .top)
                        }
                        if conversations.isEmpty {
                            // Inside the List, so the chips and the Archived row above still render.
                            Text(filter.emptyMessage)
                                .font(.appTextMedium)
                                .foregroundStyle(Color.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 32)
                                .listRowSeparator(.hidden)
                        }
                        ForEach(Array(conversations.enumerated()), id: \.element.id) { index, conversation in
                            TipConversationRow(conversation: conversation) {
                                router.push(.tipConversation(conversation.id))
                            }
                            // Separators divide rows from each other; the first
                            // row's leading one just draws a line under the bar.
                            .listRowSeparator(index == 0 ? .hidden : .automatic, edges: .top)
                            // Mute first: the first button is the outer, full-swipe action.
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                muteAction(for: conversation)
                                archiveAction(for: conversation)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .onScrollGeometryChange(for: CGFloat.self) { geometry in
                        geometry.contentOffset.y + geometry.contentInsets.top
                    } action: { _, offset in
                        // Overscrolling past the top reveals; scrolling a little way down hides.
                        // The gap between the two thresholds stops the reveal from flickering when
                        // the row's own height shifts the list.
                        if offset < -60, !chipsPulledDown {
                            withAnimation(.easeOut(duration: 0.2)) { chipsPulledDown = true }
                        } else if offset > 24, chipsPulledDown, filter == .all {
                            withAnimation(.easeOut(duration: 0.2)) { chipsPulledDown = false }
                        }
                    }
                }
                .animation(.easeOut(duration: 0.2), value: chipsVisible)
            }
        }
        .overlay(alignment: .bottom) {
            if undoTarget != nil {
                ArchiveUndoToast {
                    if let id = undoTarget { conversationController.unarchive(id) }
                    undoTarget = nil
                }
                .padding(.bottom, 16)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.default, value: undoTarget)
        // Dismisses itself, like the reaction error toast; a new archive restarts the clock.
        .task(id: undoTarget) {
            guard undoTarget != nil else { return }
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled { undoTarget = nil }
        }
        .sheet(item: $muteTarget) { target in
            MuteChatSheet(conversationID: target.id, isPresented: isPickingMuteDuration)
        }
        .navigationTitle("Chat")
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
        .task(id: conversationController.chatListConversations.count) {
            let selfUserID = conversationController.selfUserID
            let subjects: [(subject: ProfileAvatarStore.AvatarSubject, picture: ProfilePicture?)] =
                conversationController.chatListConversations.map { conversation in
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
        // Name the group senders a row's roster subset leaves out. Keyed on that set, so it runs when
        // a new last message comes from someone nothing here can name, and not again once the
        // directory has landed them. The reload comes first: `resolve` skips only what the snapshot
        // already holds, and at launch the snapshot has not read the cache yet.
        .task(id: unnamedSenders) {
            guard !unnamedSenders.isEmpty else { return }
            await sessionContainer.knownAuthors.reload()
            await sessionContainer.knownAuthors.resolve(unnamedSenders)
        }
    }

    /// Group senders of the listed rows' last messages that nothing on the device can name yet.
    private var unnamedSenders: [UserID] {
        conversationController.unnamedLastMessageSenders(
            in: conversationController.chatListConversations,
            knownAuthors: sessionContainer.knownAuthors.snapshot
        )
    }

    /// The row's trailing swipe action, which opens the same duration picker as the chat's
    /// settings screen rather than toggling the mute itself.
    private func muteAction(for conversation: Conversation) -> some View {
        let isMuted = conversation.isMuted(at: .now)
        let symbol: SystemSymbol = isMuted ? .bell : .bellSlash
        return Button {
            muteTarget = MuteTarget(id: conversation.id)
        } label: {
            // A swipe action draws its label white whatever the style says, so the amber has to be
            // baked into the image.
            Image(uiImage: UIImage(systemName: symbol.rawValue)!
                .withTintColor(UIColor(Color.warning), renderingMode: .alwaysOriginal))
        }
        // The mute chip's amber-on-amber, not the delete red: nothing is lost by it.
        .tint(.warningSecondary)
        .accessibilityLabel(isMuted ? "Change mute" : "Mute notifications")
    }

    /// The row's inner swipe action. Mute stays the outer, full-swipe one, so reaching this takes a
    /// partial swipe and a tap.
    private func archiveAction(for conversation: Conversation) -> some View {
        Button {
            conversationController.archive(conversation.id)
            undoTarget = conversation.id
        } label: {
            Image(systemName: "archivebox")
        }
        .tint(.backgroundRow)
        // A swipe action is also a VoiceOver custom action, next to the mute one.
        .accessibilityLabel("Archive chat")
    }

    /// Bridges ``MuteChatSheet``'s dismissal binding onto ``muteTarget``.
    private var isPickingMuteDuration: Binding<Bool> {
        Binding(
            get: { muteTarget != nil },
            set: { if !$0 { muteTarget = nil } }
        )
    }
}

/// The chat whose mute sheet is open. A wrapper because ``ConversationID`` isn't `Identifiable`,
/// and `.sheet(item:)` keeps the item through the dismissal animation where an optional-backed
/// `isPresented` would blank the sheet's content on the way out.
private struct MuteTarget: Identifiable {
    let id: ConversationID
}

// MARK: - NewChatButton -

/// The Chat tab's new-chat affordance, a bar item beside the "Chat" title.
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
struct TipConversationRow: View {

    let conversation: Conversation
    let onTap: () -> Void

    @Environment(ConversationController.self) private var conversationController
    @Environment(SessionContainer.self) private var sessionContainer
    @Environment(Session.self) private var session
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
        let unreadCount = hasUnread ? conversationController.unreadCount(for: conversation) : nil
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
            accessibilityLabel: accessibilityLabel(title: title, hasUnread: hasUnread, unreadCount: unreadCount, isMuted: isMuted),
            onTap: onTap
        ) {
            RecipientRowAccessory(
                timestamp: conversation.lastActivity,
                isUnknown: false,
                hasUnread: hasUnread,
                unreadCount: unreadCount
            )
        }
        .accessibilityIdentifier(chatTypeIdentifier)
        .task(id: avatarSubject) {
            await sessionContainer.profileAvatars.load(avatarSubject, picture: avatarPicture)
        }
        // Keyed on the watermark and the newest message, the two things the count reads, so a
        // row whose count can't be known yet fetches again when either moves.
        .task(id: UnreadCountSubject(conversation: conversation, selfUserID: conversationController.selfUserID)) {
            await conversationController.resolveUnreadCount(for: conversation)
        }
    }

    /// The preview line: the last message, or an italic "Nothing yet" for a chat with no message
    /// at all. A group is created empty, and a blank line there reads as a row still loading.
    /// Only a chat that never had a message gets the placeholder — a last message the preview
    /// declines to quote (a tombstone, an empty body) is not nothing, so it leaves the line off.
    private var subtitle: AttributedString? {
        if let preview = conversationController.lastMessagePreview(
            for: conversation,
            knownAuthors: sessionContainer.knownAuthors.snapshot,
            currencyName: { session.balance(for: $0)?.name }
        ) {
            return AttributedString(preview)
        }
        guard conversation.lastMessage == nil else { return nil }
        var placeholder = AttributedString("Nothing yet")
        // Not an emphasis intent: the bundled Avenir has no italic, so asking for one renders upright.
        placeholder.font = .defaultOblique(size: 14, weight: .bold, dynamicTypeSize: dynamicTypeSize)
        return placeholder
    }

    /// Names the row's chat type, so UI tests can tell a tip DM from a group — the label is only a name.
    private var chatTypeIdentifier: String {
        switch conversation.type {
        case .tipDm:     "chat-row-tip-dm"
        case .contactDm: "chat-row-contact-dm"
        case .group:     "chat-row-group"
        }
    }

    /// The row reads as one element, so the bell's own label is discarded — it has to be said here.
    private func accessibilityLabel(title: String, hasUnread: Bool, unreadCount: Int?, isMuted: Bool) -> String {
        [title, hasUnread ? unreadLabel(count: unreadCount) : nil, isMuted ? "muted" : nil]
            .compactMap { $0 }
            .joined(separator: ", ")
    }

    /// The count when the row shows one, else the bare state the dot stands for.
    private func unreadLabel(count: Int?) -> String {
        switch count {
        case .some(1): "1 unread message"
        case .some(let count) where count > 1: "\(count) unread messages"
        case .some, .none: "unread messages"
        }
    }
}

/// What a row's unread count reads: the viewer's READ watermark and the newest message.
private struct UnreadCountSubject: Equatable {
    let readPointer: MessageID?
    let lastMessageID: MessageID?

    init(conversation: Conversation, selfUserID: UserID?) {
        readPointer = conversation.selfReadPointer(for: selfUserID)
        lastMessageID = conversation.lastMessage?.id
    }
}
