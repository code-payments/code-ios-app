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

    /// Whether the toolbar offers Search. Off where the iOS 26 tab bar has its own search tab.
    var showsSearchButton = true

    @State private var muteTarget: MuteTarget?
    /// The filter, chip reveal and where a tap goes. Shared with the Puppet host, which replays the
    /// Chats behavior files against it.
    @State private var model = ChatsModel<ConversationID>()
    @Environment(ToastController.self) private var toasts
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.floatingTabBar) private var floatingTabBar
    @State private var isTabBarOnSide = false
    /// The chip row's height: while hidden, the list rests scrolled down by exactly this much.
    @State private var chipsHeight: CGFloat = 0
    /// The hidden chips' fade, set per frame by the scroll view. Only the chip row reads it, so a
    /// pull doesn't re-render the whole list every frame.
    @State private var chipFade = ChipFade()
    /// Select mode, owned by the tab view so it can swap the tab bar for the action capsules. Where no
    /// tab view provides one (the `.tips` sheet), the screen keeps its own.
    @Environment(ChatSelection.self) private var sharedSelection: ChatSelection?
    @State private var localSelection = ChatSelection()

    private var selection: ChatSelection { sharedSelection ?? localSelection }

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
        return model.visibleIDs(in: projection).compactMap { byID[$0] }
    }

    /// A selected filter keeps the chips in view: they explain the list.
    private var showsChips: Bool { model.showsChips }

    private var filter: Binding<ChatListFilter> {
        Binding(get: { model.filter }, set: { model.select($0) })
    }

    /// Pushes the screen ``ChatsModel`` sends the user to.
    private func open(_ destination: ChatsDestination<ConversationID>) {
        switch destination {
        case .chat(let id): router.push(.tipConversation(id))
        case .archived: router.push(.archivedChats)
        case .newChat: router.push(.newChat)
        }
    }

    var body: some View {
        let projection = self.projection
        let conversations = rows(projection)
        let nothingAtAll = ChatsModel.hasNoChatsAtAll(in: projection)

        Background(color: .backgroundMain) {
            if nothingAtAll {
                // Blank until the feed is known, so a cold launch onto this tab doesn't flash "No
                // Chats Yet" in the moment before the cache hydrates.
                if conversationController.hasResolvedFeed {
                    NoChatsView()
                }
            } else {
                List {
                        // Always the first row, so the chips scroll with the list. Hidden means the
                        // list rests scrolled just past them, so a pull drags them on with the
                        // finger. The chips use a custom button style, which keeps each chip's tap
                        // its own inside the row.
                        FadingChips(fade: chipFade, isShown: showsChips) {
                            ChatListChips(selection: filter, projection: projection)
                        }
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                                chipsHeight = $0
                            }
                            .background {
                                ChipRevealScrollHook(
                                    chipsHeight: chipsHeight,
                                    isRevealed: showsChips,
                                    fade: chipFade,
                                    reveal: { model.revealChips() }
                                )
                            }
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        // Only under All: the other filters narrow the list, and archived chats aren't in it.
                        if model.showsArchivedRow(in: projection) {
                            ArchivedRow(count: projection.archivedRowCount) {
                                open(model.openArchived())
                            }
                            .listRowSeparator(.hidden, edges: .top)
                            .listRowBackground(Color.clear)
                        }
                        ForEach(Array(conversations.enumerated()), id: \.element.id) { index, conversation in
                            TipConversationRow(
                                conversation: conversation,
                                selection: isSelecting ? selection.selected.contains(conversation.id) : nil
                            ) {
                                if isSelecting {
                                    selection.toggle(conversation.id)
                                } else {
                                    open(model.openChat(conversation.id))
                                }
                            }
                            // Separators divide rows from each other; the first
                            // row's leading one just draws a line under the bar.
                            .listRowSeparator(index == 0 ? .hidden : .automatic, edges: .top)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                if !isSelecting {
                                    // First is outermost and takes the full swipe: Archive, the
                                    // action that takes the row out of the list.
                                    archiveAction(for: conversation)
                                    muteAction(for: conversation)
                                }
                            }
                            .chatRowActions(
                                for: conversation,
                                in: .main,
                                isEnabled: !isSelecting,
                                onMute: { muteTarget = MuteTarget(ids: [conversation.id]) },
                                onArchive: { archive([conversation.id]) }
                            )
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: isSelecting)
                    // With no tab bar below to stand in for (the `.tips` sheet, the pre-iOS 26
                    // pill, which hides for select mode, or a bar on a side edge), the capsules
                    // take an inset of their own so the last row scrolls clear of them.
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        if isSelecting, !capsulesTakeTabBarSlot {
                            selectionActions(for: conversations)
                                .padding(.bottom, 8)
                                .transition(capsuleTransition)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    // With the tab bar on a side edge nothing sits along the bottom, and the blur
                    // the search field adds there would otherwise linger after Search closes.
                    // `tabBarPlacement` still reads `.bottomBar` there, so this goes by which
                    // edge the bar's inset lands on.
                    .hidesBottomScrollEdge(isTabBarOnSide)
                    .onGeometryChange(for: Bool.self) { proxy in
                        let insets = proxy.safeAreaInsets
                        return max(insets.leading, insets.trailing) > insets.bottom
                    } action: { isTabBarOnSide = $0 }
                    // Over the faded system tab bar, in its pill's slot just below the list's
                    // safe area: the bar keeps its inset, so the list's bottom blur stays exactly
                    // as it is behind the tab bar.
                    .overlay(alignment: .bottom) {
                        if isSelecting, capsulesTakeTabBarSlot {
                            selectionActions(for: conversations)
                                .frame(height: Self.tabBarPillHeight)
                                .offset(y: Self.tabBarPillHeight)
                                .transition(capsuleTransition)
                        }
                    }
                    .overlay {
                        // Over the List rather than a row in it, so it centres in the whole
                        // screen and the List keeps the pull that reveals the chips.
                        if conversations.isEmpty {
                            Text(model.filter.emptyMessage)
                                .font(.appTextMedium)
                                .foregroundStyle(Color.textSecondary)
                                .allowsHitTesting(false)
                        }
                    }
            }
        }
        .sheet(item: $muteTarget) { target in
            MuteChatSheet(conversationIDs: target.ids, isPresented: isPickingMuteDuration)
        }
        .navigationTitle(isSelecting ? "\(selection.selected.count) Selected" : "Chat")
        .toolbarTitleDisplayMode(.inline)
        // An archived or left chat drops out of the picks, so no action reaches a chat no longer listed.
        .onChange(of: conversationController.chatListProjection.main) { _, ids in
            selection.retain(Set(ids))
        }
        // Select mode belongs to the visible list; leaving the screen leaves it.
        .onDisappear { selection.end() }
        .toolbar {
            if isSelecting {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { setSelecting(false) }
                        .font(.appTextMedium)
                        .foregroundStyle(Color.textMain)
                        .accessibilityIdentifier("chat-select-done")
                }
            } else {
                ToolbarItem(placement: .topBarLeading) {
                    ChatListMoreMenu(
                        canReadAll: conversationController.hasUnreadInChatList,
                        onSelect: { setSelecting(true) },
                        onReadAll: confirmReadAll
                    )
                }
                toolbarTrailingItems
            }
        }
        // Search filters currencies by name over what Discover returned; fetched here so the
        // Currencies results are ready by the time Search opens.
        .task {
            await sessionContainer.discoveredCurrencies.refresh()
        }
        // Takes a finished cache read before the first frame, instead of drawing empty until launch
        // work lets the controller's own hydration run.
        .onAppear {
            // Names first: the cache hydration below invalidates the rows, and they must not
            // render once without them.
            sessionContainer.knownAuthors.hydrateIfReady()
            conversationController.hydrateIfReady()
        }
        // Lobby updates sit outside the event log, so the list rereads every hosted lobby on load.
        .task {
            await sessionContainer.hostedLobbies.refresh(hosted: conversationController.hostedPrivateGroupIDs)
        }
        // No push says a join request was decided, so the list asks after each one it opens on;
        // an admission seats the group and puts it in the list.
        .task {
            let lobbyRequests = sessionContainer.lobbyRequests
            await lobbyRequests.conversationIDs.concurrentForEach { @MainActor [conversationController] conversationID in
                if let fresh = await conversationController.refreshRequestedGroup(conversationID) {
                    lobbyRequests.reconcile(with: fresh)
                }
            }
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

    private var isSelecting: Bool { selection.isActive }

    /// The height of the iOS 26 system tab bar's pill, measured on a 402pt-wide iPhone.
    private static let tabBarPillHeight: CGFloat = 62

    /// Whether a system tab bar sits below the list, faded out for select mode, so the capsules can
    /// take its pill's slot. The legacy pill hides instead, which clears `floatingTabBar`.
    private var capsulesTakeTabBarSlot: Bool {
        floatingTabBar != nil && !isTabBarOnSide
    }

    private var capsuleTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.9, anchor: .bottom))
    }

    private func selectionActions(for conversations: [Conversation]) -> some View {
        ChatSelectionActions(
            selected: selectedIDs(in: conversations),
            onReadAll: confirmReadAll,
            onMute: { ids in
                muteTarget = MuteTarget(ids: ids)
                setSelecting(false)
            },
            onArchive: { ids in
                archive(ids)
                setSelecting(false)
            },
            onDone: { setSelecting(false) }
        )
    }

    /// Enters or leaves select mode, cross-fading the tab bar and the capsules in one animation.
    private func setSelecting(_ isOn: Bool) {
        let animation: Animation = reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.4, bounce: 0.15)
        withAnimation(animation) {
            if isOn { selection.begin() } else { selection.end() }
        }
    }

    @ToolbarContentBuilder private var toolbarTrailingItems: some ToolbarContent {
        if showsSearchButton {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    router.push(.chatSearch)
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .accessibilityLabel("Search")
                .accessibilityIdentifier("chat-search-button")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            NewChatButton { open(model.openNewChat()) }
        }
    }

    /// The picks, in list order, limited to rows still listed.
    private func selectedIDs(in conversations: [Conversation]) -> [ConversationID] {
        conversations.map(\.id).filter(selection.selected.contains)
    }

    /// Archives `ids` with one toast whose Undo restores all of them.
    private func archive(_ ids: [ConversationID]) {
        guard !ids.isEmpty else { return }
        conversationController.archive(ids)
        toasts.show(.archivedChats(count: ids.count) { conversationController.unarchive(ids) })
    }

    /// Read All asks first: it sends read receipts to every unread chat.
    private func confirmReadAll() {
        sessionContainer.session.dialogItem = .markAllChatsRead {
            conversationController.readAllChats()
            setSelecting(false)
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
            muteTarget = MuteTarget(ids: [conversation.id])
        } label: {
            SwipeActionLabel(title: isMuted ? "Unmute" : "Mute", systemImage: symbol.rawValue, glyphColor: .warning)
        }
        // The mute chip's amber-on-amber, not the delete red: nothing is lost by it.
        .tint(.warningSecondary)
        .accessibilityLabel(isMuted ? "Change mute" : "Mute notifications")
    }

    /// The row's inner swipe action. Mute stays the outer, full-swipe one, so reaching this takes a
    /// partial swipe and a tap.
    private func archiveAction(for conversation: Conversation) -> some View {
        Button {
            archive([conversation.id])
        } label: {
            SwipeActionLabel(title: "Archive", systemImage: "archivebox")
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
    let ids: [ConversationID]
    var id: [ConversationID] { ids }
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

    let action: () -> Void

    var body: some View {
        Button(action: action) {
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
    /// Select mode: nil outside it; otherwise whether the row is picked.
    var selection: Bool? = nil
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
        let joinRequests = ChatRowJoinRequests(conversationController.joinRequests(for: conversation.id))
        let hasUnreadMessages = conversationController.hasUnreadMessages(conversation)
        let unreadMessageCount = hasUnreadMessages ? conversationController.unreadCount(for: conversation) : nil
        let subtitle = joinRequests.subtitle(preview: self.subtitle, hasUnreadMessages: hasUnreadMessages)
        // Marked unread with nothing unread draws the no-count state; a known count still wins.
        let isMarkedUnread = !hasUnreadMessages && conversationController.isMarkedUnread(conversation.id)
        let hasUnread = hasUnreadMessages || joinRequests.count > 0 || isMarkedUnread
        let unreadCount = joinRequests.pillCount(hasUnreadMessages: hasUnreadMessages, unreadMessageCount: unreadMessageCount)
        // A pending request moves the row up, so the time shown is the one it sorts by.
        let timestamp = conversationController.chatListJoinRequests(for: conversation.id)
            .sortTime(after: conversation.lastActivity)
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
            selection: selection,
            accessibilityLabel: accessibilityLabel(
                title: title,
                joinRequests: joinRequests.line,
                hasUnreadMessages: hasUnreadMessages || isMarkedUnread,
                unreadMessageCount: unreadMessageCount,
                isMuted: isMuted
            ),
            onTap: onTap
        ) {
            RecipientRowAccessory(
                timestamp: timestamp,
                isUnknown: false,
                hasUnread: hasUnread,
                unreadCount: unreadCount,
                showsChevron: selection == nil
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
        // A request's preview names its title, which only the request itself carries, sealed to the chat.
        .task(id: lastRequestID) {
            guard let lastRequestID else { return }
            async let request: Void = sessionContainer.paymentRequests.fetchIfMissing(lastRequestID)
            async let seal: Void = sessionContainer.paymentRequests.loadSeal(for: conversation.id)
            _ = await (request, seal)
        }
    }

    private var lastRequestID: PaymentRequestID? {
        guard let message = conversation.lastMessage else { return nil }
        if case .widget(.paymentRequest(let id)) = message.content { return id }
        // A share payment's preview names its request too.
        return message.paymentRequestID
    }

    /// The preview line: the last message, or an italic placeholder for a chat with no message
    /// at all ("Nothing yet", or an invitation for a group the viewer is alone in). A group is created empty, and a blank line there reads as a row still loading.
    /// Only a chat that never had a message gets the placeholder — a last message the preview
    /// declines to quote (a tombstone, an empty body) is not nothing, so it leaves the line off.
    private var subtitle: AttributedString? {
        if let preview = conversationController.lastMessagePreview(
            for: conversation,
            knownAuthors: sessionContainer.knownAuthors.snapshot,
            viewerAmount: session.displayCurrency.amount,
            requestTitle: { id in
                sessionContainer.paymentRequests.request(id).flatMap(sessionContainer.paymentRequests.text)?.title
            },
            currencyName: { session.balance(for: $0)?.name }
        ) {
            return AttributedString(preview)
        }
        guard conversation.lastMessage == nil else { return nil }
        var placeholder = AttributedString(GroupReadyCard.emptyPreview(for: conversation))
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
    private func accessibilityLabel(
        title: String,
        joinRequests: String?,
        hasUnreadMessages: Bool,
        unreadMessageCount: Int?,
        isMuted: Bool
    ) -> String {
        [title, joinRequests, hasUnreadMessages ? unreadLabel(count: unreadMessageCount) : nil, isMuted ? "muted" : nil]
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

/// Drives the hidden chip row through the UIKit scroll view behind the chat List, whose scroll
/// position and release target SwiftUI's scroll modifiers don't reach. While the chips are hidden
/// it opens the list scrolled just past them, lands a release on the chips or just past them
/// rather than between, and stops a fling from mid-list just past them.
private struct ChipRevealScrollHook: UIViewRepresentable {
    let chipsHeight: CGFloat
    let isRevealed: Bool
    let fade: ChipFade
    let reveal: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> HookView {
        let view = HookView()
        view.isUserInteractionEnabled = false
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ view: HookView, context: Context) {
        let coordinator = context.coordinator
        coordinator.chipsHeight = chipsHeight
        coordinator.isRevealed = isRevealed
        coordinator.fade = fade
        coordinator.reveal = reveal
        coordinator.attach(from: view)
    }

    /// Attaches as soon as it joins the List's hierarchy, so the list is parked before its first
    /// frame draws rather than a run-loop turn later, with the chips briefly on screen.
    final class HookView: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil { coordinator?.attach(from: self) }
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var chipsHeight: CGFloat = 0
        var isRevealed = false
        var reveal: () -> Void = {}
        var fade: ChipFade?
        /// Set when a release commits to the chips; applied once the list comes to rest on them,
        /// so the state change doesn't re-render the list mid-motion.
        private var pendingReveal = false

        private weak var scrollView: UIScrollView?
        private var observations: [NSKeyValueObservation] = []
        private var parked = false
        private var pullStartedAtTop = false

        func attach(from view: UIView) {
            if scrollView == nil {
                guard let found = Self.enclosingScrollView(of: view) else { return }
                scrollView = found
                found.panGestureRecognizer.addTarget(self, action: #selector(pan(_:)))
                observations = [
                    found.observe(\.contentSize) { [weak self] _, _ in
                        MainActor.assumeIsolated { self?.parkIfNeeded() }
                    },
                    found.observe(\.contentOffset) { [weak self] _, _ in
                        MainActor.assumeIsolated { self?.offsetChanged() }
                    },
                ]
            }
            parkIfNeeded()
        }

        /// Scroll distance from the list's top, in points.
        private func distance(_ scrollView: UIScrollView) -> CGFloat {
            scrollView.contentOffset.y + scrollView.adjustedContentInset.top
        }

        private func setDistance(_ value: CGFloat, animated: Bool) {
            guard let scrollView else { return }
            let y = value - scrollView.adjustedContentInset.top
            scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: y), animated: animated)
        }

        /// Opens the list with the chips scrolled just out of view, once.
        private func parkIfNeeded() {
            guard !parked, !isRevealed, chipsHeight > 0,
                  let scrollView, scrollView.contentSize.height > chipsHeight else { return }
            parked = true
            if distance(scrollView) < chipsHeight { setDistance(chipsHeight, animated: false) }
        }

        @objc private func pan(_ gesture: UIPanGestureRecognizer) {
            guard let scrollView, !isRevealed, chipsHeight > 0 else { return }
            switch gesture.state {
            case .began:
                pullStartedAtTop = distance(scrollView) <= chipsHeight + 1
            case .ended, .cancelled:
                // Where the release is heading, so a flick counts as well as a slow drag.
                let velocity = gesture.velocity(in: scrollView).y
                let projected = distance(scrollView) - velocity * 0.1
                guard distance(scrollView) < chipsHeight || projected < chipsHeight else { return }
                if pullStartedAtTop, projected < chipsHeight / 2 {
                    pendingReveal = true
                    // Pulled past the top, the system's bounce already lands on the chips; moving
                    // the offset under it would stack a second motion on the bounce.
                    if distance(scrollView) > 0 { setDistance(0, animated: true) }
                } else if distance(scrollView) < chipsHeight {
                    setDistance(chipsHeight, animated: true)
                }
            default:
                break
            }
        }

        /// A fling that didn't start at the top stops just past the hidden chips, as if they weren't there.
        private func offsetChanged() {
            guard let scrollView, chipsHeight > 0 else { return }
            let distance = distance(scrollView)
            if !isRevealed {
                let progress = (min(max(1 - distance / chipsHeight, 0), 1) * 100).rounded() / 100
                if fade?.progress != progress { fade?.progress = progress }
            }
            if pendingReveal, abs(distance) < 0.5 {
                pendingReveal = false
                reveal()
            }
            stopFlingAtChips()
        }

        private func stopFlingAtChips() {
            guard let scrollView, !isRevealed, parked, chipsHeight > 0,
                  scrollView.isDecelerating, !pullStartedAtTop,
                  distance(scrollView) < chipsHeight else { return }
            setDistance(chipsHeight, animated: false)
        }

        private static func enclosingScrollView(of view: UIView) -> UIScrollView? {
            var current = view.superview
            while let candidate = current {
                if let scrollView = candidate as? UIScrollView { return scrollView }
                current = candidate.superview
            }
            return nil
        }
    }
}

/// How much of the hidden chip row a pull has brought on screen, from 0 to 1.
@Observable
private final class ChipFade {
    var progress: Double = 0
}

/// Reads the fade on its own, so the per-frame changes re-render only the chips.
private struct FadingChips<Content: View>: View {
    let fade: ChipFade
    let isShown: Bool
    @ViewBuilder let content: Content

    var body: some View {
        content.opacity(isShown ? 1 : fade.progress)
    }
}
