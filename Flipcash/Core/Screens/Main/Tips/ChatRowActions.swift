//
//  ChatRowActions.swift
//  Flipcash
//

import SwiftUI
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
        if isEnabled, let action = conversationController.readAction(for: conversation) {
            content
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button {
                        conversationController.perform(action, on: conversation.id, source: .swipe)
                    } label: {
                        Label(action.title, systemImage: action.systemImage)
                            .labelStyle(.iconOnly)
                    }
                    .tint(.unreadIndicator)
                    .accessibilityLabel(action.title)
                }
                .modifier(ChatRowContextMenu(
                    conversation: conversation,
                    action: action,
                    list: list,
                    onMute: onMute,
                    onArchive: onArchive
                ))
        } else {
            content
        }
    }
}

/// The long-press menu. A chat with a message in the local store previews its transcript above the
/// menu; one with none shows the menu alone.
private struct ChatRowContextMenu: ViewModifier {

    let conversation: Conversation
    let action: ChatReadAction
    let list: ChatRowList
    let onMute: () -> Void
    let onArchive: () -> Void

    @Environment(ConversationController.self) private var conversationController

    func body(content: Content) -> some View {
        if conversation.lastMessage != nil {
            content.contextMenu {
                items
            } preview: {
                ChatPreview(conversation: conversation)
                    // The preview is hosted outside this view's tree, so the controller is handed on.
                    .environment(conversationController)
            }
        } else {
            content.contextMenu { items }
        }
    }

    @ViewBuilder private var items: some View {
        Button(action.title, systemImage: action.systemImage) {
            conversationController.perform(action, on: conversation.id, source: .menu)
        }
        if conversationController.isMuted(conversationID: conversation.id) {
            Button("Unmute", systemImage: SystemSymbol.bell.rawValue) {
                Task { try? await conversationController.unmute(conversationID: conversation.id) }
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

// MARK: - Preview -

/// The long-press preview: the chat's last messages from the local store, read-only, with no input
/// bar. Nothing here touches the read pointer: it is not `ConversationScreen`, which marks messages
/// seen as they appear, so looking leaves the chat as unread as it was.
struct ChatPreview: View {

    let conversation: Conversation

    @Environment(ConversationController.self) private var conversationController

    var body: some View {
        let messages = conversationController.previewMessages(for: conversation)
        let selfUserID = conversationController.selfUserID

        VStack(alignment: .leading, spacing: 0) {
            Text(conversationController.displayName(for: conversation))
                .font(.appTextMedium)
                .foregroundStyle(Color.textMain)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            Divider().overlay(Color.rowSeparator)
            VStack(spacing: 6) {
                Spacer(minLength: 0)
                ForEach(messages, id: \.id) { message in
                    if let text = conversationController.messagePreview(
                        message,
                        in: conversation,
                        currencyName: { _ in nil }
                    ) {
                        ChatPreviewBubble(text: text, isFromSelf: message.isFromSelf(selfUserID))
                    }
                }
            }
            .padding(12)
        }
        .frame(width: 340, height: 430)
        .background(Color.backgroundMain)
    }
}

/// One message in the preview: the transcript's sides, without its cells.
private struct ChatPreviewBubble: View {

    let text: String
    let isFromSelf: Bool

    var body: some View {
        Text(text)
            .font(.appTextMedium)
            .foregroundStyle(Color.textMain)
            .lineLimit(4)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isFromSelf ? Color.backgroundSecondary : Color.backgroundRow, in: .rect(cornerRadius: 16))
            .frame(maxWidth: 260, alignment: isFromSelf ? .trailing : .leading)
            .frame(maxWidth: .infinity, alignment: isFromSelf ? .trailing : .leading)
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
            Button("Read All", systemImage: "message", action: onReadAll)
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
                    Task { try? await conversationController.unmute(ids) }
                    onDone()
                }
            }
            .disabled(!hasSelection)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
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
                .selectionCapsuleGlass()
        }
        .buttonStyle(.plain)
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
