//
//  ChatRowActions.swift
//  Flipcash
//

import SwiftUI
import UIKit
import FlipcashCore
import FlipcashUI

/// Which list a row sits in: the third long-press item archives on the main list and unarchives on
/// the archived one.
enum ChatRowList {
    case main
    case archived
}

extension View {

    /// A chat row's leading read swipe and its long-press menu. Off in select mode, and for a chat
    /// the user can't mark (one still in Requests), where neither appears.
    ///
    /// - Parameters:
    ///   - onMute: opens ``MuteChatSheet`` for the chat, as the trailing swipe does.
    ///   - onArchive: archives (main list) or unarchives (archived list) the chat, toast included.
    func chatRowActions(
        for conversation: Conversation,
        in list: ChatRowList,
        isEnabled: Bool,
        onMute: @escaping () -> Void,
        onArchive: @escaping () -> Void
    ) -> some View {
        modifier(ChatRowActionsModifier(
            conversation: conversation,
            list: list,
            isEnabled: isEnabled,
            onMute: onMute,
            onArchive: onArchive
        ))
    }
}

private struct ChatRowActionsModifier: ViewModifier {

    let conversation: Conversation
    let list: ChatRowList
    let isEnabled: Bool
    let onMute: () -> Void
    let onArchive: () -> Void

    @Environment(ConversationController.self) private var conversationController

    func body(content: Content) -> some View {
        // One modifier chain whether or not the actions are on; only what's inside empties. Branching
        // on `isEnabled` gave select mode a different view, so the List swapped the row for a new one
        // and cross-faded the two while the select circle slid in.
        let action = isEnabled ? conversationController.readAction(for: conversation) : nil
        content
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                if let action {
                    Button {
                        conversationController.perform(action, on: conversation.id, source: .swipe)
                    } label: {
                        SwipeActionLabel(
                            title: action.swipeTitle,
                            systemImage: action.systemImage,
                            glyphColor: .unreadIndicator
                        )
                    }
                    // Mute's tonal style in blue: the glyph on its own colour at low strength.
                    .tint(.unreadIndicatorSecondary)
                    .accessibilityLabel(action.title)
                }
            }
            .modifier(ChatRowContextMenu(
                conversation: conversation,
                action: action,
                list: list,
                onMute: onMute,
                onArchive: onArchive
            ))
    }
}

/// The long-press menu. A chat with a message in the local store previews its transcript above the
/// menu; one with none shows the menu alone. With no `action` the menu has no items, which turns the
/// long press off.
private struct ChatRowContextMenu: ViewModifier {

    let conversation: Conversation
    let action: ChatReadAction?
    let list: ChatRowList
    let onMute: () -> Void
    let onArchive: () -> Void

    @Environment(ConversationController.self) private var conversationController
    @Environment(SessionContainer.self) private var sessionContainer
    @Environment(Session.self) private var session
    @Environment(Container.self) private var container

    func body(content: Content) -> some View {
        if conversation.lastMessage != nil {
            content.contextMenu {
                items
            } preview: {
                // Hosted outside this view's tree, so its dependencies are handed on.
                ChatRowPreview(
                    conversationID: conversation.id,
                    conversationController: conversationController,
                    session: session,
                    sessionContainer: sessionContainer,
                    toasts: container.toasts
                )
            }
        } else {
            content.contextMenu { items }
        }
    }

    @ViewBuilder private var items: some View {
        if let action {
            Button(action.title, systemImage: action.systemImage) {
                conversationController.perform(action, on: conversation.id, source: .menu)
            }
            if conversationController.isMuted(conversationID: conversation.id) {
                Button("Unmute", systemImage: SystemSymbol.bell.rawValue) {
                    Task { await conversationController.unmuteReporting([conversation.id], session: session) }
                }
            } else {
                Button("Mute", systemImage: SystemSymbol.bellSlash.rawValue, action: onMute)
            }
            switch list {
            case .main:
                Button("Archive", systemImage: "archivebox", action: onArchive)
            case .archived:
                Button("Unarchive", systemImage: "tray.and.arrow.up", action: onArchive)
            }
        }
    }
}

// MARK: - Preview -

/// Builds ``ChatPreview`` in `body`, which runs only once the preview shows.
///
/// `contextMenu` evaluates its preview closure every time the row updates, and every row updates
/// together when select mode starts or the "…" menu opens. Building the coordinator there read and
/// mapped each listed chat's messages on the main thread, stalling the first frames of both.
private struct ChatRowPreview: View {

    let conversationID: ConversationID
    let conversationController: ConversationController
    let session: Session
    let sessionContainer: SessionContainer
    let toasts: ToastController

    var body: some View {
        ChatPreview(
            coordinator: ConversationLoadCoordinator(
                conversationID: conversationID,
                controller: conversationController,
                session: session,
                knownAuthors: sessionContainer.knownAuthors,
                paymentRequests: sessionContainer.paymentRequests,
                openingLoadLanded: true
            ),
            conversationController: conversationController,
            linkCardSource: sessionContainer.linkCardFeed,
            knownAuthors: sessionContainer.knownAuthors,
            avatarData: { [profileAvatars = sessionContainer.profileAvatars] in profileAvatars.data(for: $0) },
            loadAvatars: { [profileAvatars = sessionContainer.profileAvatars] in profileAvatars.preload($0) },
            // The chat's own photo lookups, as `ConversationScreen` passes them, so a photo row
            // downloads its image instead of staying an empty placeholder.
            mintMediaURL: { [flipClient = sessionContainer.flipClient, owner = session.ownerKeyPair, conversationID] blobID in
                try await flipClient.blobDownloadURL(blobID: blobID, owner: owner, accessContext: .chatMessage(conversationID))
            },
            mediaBlobDecrypt: { [conversationController, conversationID] in
                await conversationController.mediaBlobDecrypt(for: conversationID)
            },
            toasts: toasts
        )
        // Mounted only while the menu is up, so it brackets the presentation.
        .onAppear { ChatListBackdrop.present() }
        .onDisappear { ChatListBackdrop.dismiss() }
    }
}

/// Frosts the screen behind a chat row's long-press preview with the blur a chat puts behind a
/// long-pressed message: the same ``MessageBackdrop``, so the material, strength, and fade match.
///
/// The system menu adds its own dimming above it, which SwiftUI's `contextMenu` offers no way to
/// turn off, so the frost reads darker here than in a chat. One shared backdrop, since only one
/// menu can be up at a time.
@MainActor
private enum ChatListBackdrop {

    private static let backdrop = MessageBackdrop()

    /// Whether the menu is still up, so a present that runs after its dismiss does nothing.
    private static var isWanted = false

    /// Covers the window's root view, which takes in the navigation and tab bars. The menu sits in
    /// its own container above the root view, so it stays sharp.
    ///
    /// The preview appears inside UIKit's `performWithoutAnimation` while the menu presents, which
    /// would apply the fade at once, so the frost starts on the next turn of the main queue.
    static func present() {
        isWanted = true
        DispatchQueue.main.async {
            guard isWanted else { return }
            let window = UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.keyWindow }
                .first
            guard let host = window?.rootViewController?.view else { return }
            backdrop.present(over: host)
        }
    }

    static func dismiss() {
        isWanted = false
        backdrop.dismiss()
    }
}

/// The long-press preview: the chat's own transcript (the same cells, background, date separators,
/// sender names and reactions), read-only, with no input bar, opened at the newest message.
///
/// It is not `ConversationScreen`, which marks messages seen as they appear. Here read reporting is
/// off and every action is a no-op, so looking leaves the chat as unread as it was. The rows come
/// from the local store through the same ``ConversationLoadCoordinator`` the screen uses; paging
/// older history, the one path that fetches, is off too.
struct ChatPreview: View {

    let conversationController: ConversationController
    let linkCardSource: any LinkCardSource
    let knownAuthors: KnownAuthorDirectory
    let avatarData: (UserID) -> Data?
    let loadAvatars: ([(userID: UserID?, picture: ProfilePicture?)]) -> Void
    let mintMediaURL: (BlobID) async throws -> URL?
    let mediaBlobDecrypt: () async -> ChatMediaURLResolver.BlobDecrypt?
    let toasts: ToastController

    @State private var coordinator: ConversationLoadCoordinator
    @State private var barModel = ConversationBarModel()
    @State private var composer = ComposerModel()

    /// - Parameter coordinator: loads the chat's rows from the local store, as it does for the
    ///   screen; pass one built with `openingLoadLanded: true` so it doesn't wait on a fetch.
    init(
        coordinator: ConversationLoadCoordinator,
        conversationController: ConversationController,
        linkCardSource: any LinkCardSource,
        knownAuthors: KnownAuthorDirectory,
        avatarData: @escaping (UserID) -> Data?,
        loadAvatars: @escaping ([(userID: UserID?, picture: ProfilePicture?)]) -> Void,
        mintMediaURL: @escaping (BlobID) async throws -> URL?,
        mediaBlobDecrypt: @escaping () async -> ChatMediaURLResolver.BlobDecrypt?,
        toasts: ToastController
    ) {
        self.conversationController = conversationController
        self.linkCardSource = linkCardSource
        self.knownAuthors = knownAuthors
        self.avatarData = avatarData
        self.loadAvatars = loadAvatars
        self.mintMediaURL = mintMediaURL
        self.mediaBlobDecrypt = mediaBlobDecrypt
        self.toasts = toasts
        _coordinator = State(initialValue: coordinator)
    }

    var body: some View {
        transcript
            .frame(width: 340, height: 430)
            .background(Color.backgroundMain)
            // The screen's own lookups for who wrote each row, so names and pictures match the
            // chat. All three only read: the local author cache, profiles by user id, and pictures.
            .task(id: isGroup) {
                guard isGroup else { return }
                await knownAuthors.reload()
            }
            .task(id: coordinator.unattributedSenders) {
                guard !coordinator.unattributedSenders.isEmpty else { return }
                await knownAuthors.resolve(coordinator.unattributedSenders)
            }
            .task(id: coordinator.attributedMembers.compactMap(\.userID)) {
                loadAvatars(coordinator.attributedMembers.map { (userID: $0.userID, picture: $0.profilePicture) })
            }
    }

    private var isGroup: Bool {
        conversationController.conversation(withID: coordinator.conversationID)?.type == .group
    }

    /// The screen's transcript in its read-only mode.
    private var transcript: ChatScreenRepresentable {
        ChatScreenRepresentable(
            items: coordinator.items,
            onReachTop: {},
            onRetry: { _ in },
            onCashCardTap: { _ in },
            onOpenURL: { _ in },
            onMentionTap: { _ in },
            onShareProfile: { _, _ in },
            ownProfile: nil,
            onLinkCardTap: { _, _ in },
            linkCardSource: linkCardSource,
            updateAction: nil,
            toasts: toasts,
            onEncryptionMarkerTap: {},
            onInviteCardTap: {},
            onAuthorTap: { _ in },
            onMessageAction: { _, _ in },
            onQuoteTap: { _ in },
            onMessagesSeen: { _ in },
            reportsReads: false,
            jumpBadge: nil,
            onUserScrollBegan: {},
            onReactionTap: { _, _ in },
            onReactionLongPress: { _, _ in },
            onReactionAdd: { _ in },
            onReactionBoost: { _ in },
            reactionStripEntries: { _ in [] },
            onReactionStripSelect: { _, _ in },
            onReactionStripAdd: { _ in },
            showsSendCash: false,
            conversationID: coordinator.conversationID,
            symbol: "",
            onSendCash: {},
            conversationController: conversationController,
            barModel: barModel,
            composer: composer,
            editingStableID: nil,
            focusOnAppear: false,
            gate: .open,
            showsGatePlaceholder: false,
            gateMintName: nil,
            gateShortfall: nil,
            // The gate is open and its placeholder hidden, so no amount is ever drawn in it.
            gateDisplayCurrency: DisplayCurrency(currency: .usd, rates: [Rate]()),
            onGateAddFunds: {},
            onGateJoin: {},
            isJoiningChat: false,
            mentions: nil,
            authorAvatars: authorAvatars,
            mintMediaURL: mintMediaURL,
            mediaBlobDecrypt: mediaBlobDecrypt,
            isReadOnlyPreview: true
        )
    }

    /// Avatar bytes for the transcript's senders, read as the screen reads them.
    private var authorAvatars: [UserID: Data] {
        var avatars: [UserID: Data] = [:]
        for member in coordinator.attributedMembers {
            guard let userID = member.userID,
                  let data = avatarData(userID) else { continue }
            avatars[userID] = data
        }
        return avatars
    }
}

// MARK: - Read All -

extension DialogItem {

    /// Read All's confirmation: reading every chat sends read receipts, so it asks first.
    static func markAllChatsRead(onConfirm: @escaping () -> Void) -> DialogItem {
        .info(
            title: "Mark All Chats as Read?",
            subtitle: "Everyone in these chats will see that you've read their messages"
        ) {
            .standard("Mark as Read", action: onConfirm);
            .cancel()
        }
    }
}

// MARK: - "…" menu -

/// The Chats title bar's "…", opposite `+` and drawn the same way: Select Chats and Read All.
struct ChatListMoreMenu: View {

    /// Whether any chat in the main list is unread; Read All is disabled otherwise.
    let canReadAll: Bool
    let onSelect: () -> Void
    let onReadAll: () -> Void

    var body: some View {
        Menu {
            Button("Select Chats", systemImage: "checkmark.circle", action: onSelect)
            Button("Read All", systemImage: "checkmark.message", action: onReadAll)
                .disabled(!canReadAll)
        } label: {
            // Bar items get their glass from the system on iOS 26, as `+` does.
            Image(systemName: "ellipsis")
                .font(.appTextLarge)
                .foregroundStyle(Color.textMain)
        }
        .accessibilityLabel("More")
        .accessibilityIdentifier("chat-more-button")
    }
}

// MARK: - Unmute -

extension ConversationController {

    /// Unmutes `ids` the way the Mute sheet's Unmute row does: a `chatUnmuted` event per chat, and
    /// on failure the same error dialog and captured error. For the paths that skip the sheet.
    func unmuteReporting(_ ids: [ConversationID], session: Session) async {
        let chatTypes = ids.map { conversation(withID: $0)?.type }
        do {
            try await unmute(ids)
            chatTypes.forEach { Analytics.chatUnmuted(chatType: $0, error: nil) }
        } catch {
            Analytics.chatUnmuted(chatType: chatTypes.first ?? nil, error: error)
            session.dialogItem = .error(
                title: "Something Went Wrong",
                subtitle: ids.count == 1
                    ? "We were unable to unmute this chat. Please try again"
                    : "We were unable to unmute these chats. Please try again"
            )
            ErrorReporting.captureError(error, reason: "Failed to unmute chat")
        }
    }
}

// MARK: - Select mode actions -

/// Select mode's three floating capsules, in place of the tab bar: the read toggle, Archive, Mute.
/// With nothing picked the read toggle is Read All and the other two are disabled.
struct ChatSelectionActions: View {

    /// The picks, in list order.
    let selected: [ConversationID]
    let onReadAll: () -> Void
    let onMute: ([ConversationID]) -> Void
    let onArchive: ([ConversationID]) -> Void
    /// Leaves select mode once an action has run.
    let onDone: () -> Void

    @Environment(ConversationController.self) private var conversationController
    @Environment(Session.self) private var session

    var body: some View {
        let toggle = conversationController.readToggle(for: selected)
        let mute = conversationController.muteToggle(for: selected)
        let hasSelection = !selected.isEmpty

        HStack {
            ChatSelectionCapsule(title: toggle.title, identifier: "chat-select-read") {
                if toggle == .readAll {
                    onReadAll()
                } else {
                    conversationController.apply(toggle, to: selected)
                    onDone()
                }
            }
            Spacer(minLength: 8)
            ChatSelectionCapsule(title: "Archive", identifier: "chat-select-archive") {
                onArchive(selected)
            }
            .disabled(!hasSelection)
            Spacer(minLength: 8)
            ChatSelectionCapsule(title: mute.title, identifier: "chat-select-mute") {
                switch mute {
                case .mute:
                    onMute(selected)
                case .unmute:
                    let ids = selected
                    Task { await conversationController.unmuteReporting(ids, session: session) }
                    onDone()
                }
            }
            .disabled(!hasSelection)
        }
        .padding(.horizontal, 16)
    }
}

/// One select-mode capsule: a label on glass, the height of the title bar's own capsules.
private struct ChatSelectionCapsule: View {

    let title: String
    let identifier: String
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.appTextMedium)
                .foregroundStyle(isEnabled ? Color.textMain : Color.textSecondary)
                .padding(.horizontal, 20)
                .frame(height: 44)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        // Outside the button: a disabled plain button fades its label, and the glass would fade with it.
        .selectionCapsuleGlass()
        .accessibilityIdentifier(identifier)
    }
}

private extension View {

    /// Liquid Glass on iOS 26; the ultra-thin material before it, as the pin bar does.
    @ViewBuilder
    func selectionCapsuleGlass() -> some View {
        if #available(iOS 26, *) {
            glassEffect(.regular.interactive(), in: .capsule)
        } else {
            background(.ultraThinMaterial, in: .capsule)
        }
    }
}
