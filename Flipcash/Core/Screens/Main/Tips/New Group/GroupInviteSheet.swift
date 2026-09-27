//
//  GroupInviteSheet.swift
//  Flipcash
//

import SwiftUI
import UIKit
import FlipcashCore
import FlipcashUI

/// "Invite People" (nodes 10330:19387, 10330:19549, 10329:12104): hand out a group's invite link by
/// Share or Copy, or post it straight into recent chats with an optional message.
///
/// A group is not discoverable — the link built from its id is the only way in — so every path here
/// sends the same URL.
struct GroupInviteSheet: View {

    let conversationID: ConversationID

    @Binding var isPresented: Bool

    /// Called after a direct send with the chat picked first, which the presenter opens.
    let onInvited: (ConversationID) -> Void

    @Environment(ConversationController.self) private var conversationController
    @Environment(SessionContainer.self) private var sessionContainer

    /// How long the copy tile stays on its checkmark before reverting — the beat the tip-card link
    /// row holds.
    private static let confirmationDuration: Duration = .seconds(1.5)

    @State private var model: InvitePeopleViewModel
    @State private var didCopy = false
    @FocusState private var isMessageFocused: Bool

    init(conversationID: ConversationID, isPresented: Binding<Bool>, onInvited: @escaping (ConversationID) -> Void) {
        self.conversationID = conversationID
        self._isPresented = isPresented
        self.onInvited = onInvited
        self._model = State(initialValue: InvitePeopleViewModel(url: .groupChatInvite(for: conversationID)))
    }

    /// The group's own title, which names it in the shared message.
    ///
    /// Read from the record rather than through `displayName(for:)`: that resolves an untitled chat
    /// to a counterpart's name or to "Flipcash User", and a group invited to under either of those
    /// would be worse than one invited to with no name at all. Nil shares the bare link — see
    /// ``GroupInviteShareItem``.
    private var title: String? {
        conversation?.title
    }

    private var conversation: Conversation? {
        conversationController.conversation(withID: conversationID)
    }

    /// The chats the Chats tab lists, newest activity first: 1:1 chats and joined groups, less the
    /// group being invited to. Search and people outside recent chats are out of scope.
    private var recentChats: [Conversation] {
        conversationController.chatListConversations.filter { $0.id != conversationID }
    }

    /// The group's picture for the share sheet's own preview card.
    ///
    /// Decoded at the tap rather than in a computed property, so a thumbnail isn't re-decoded on
    /// every render of a sheet that shows it nowhere. Nil while the avatar hasn't loaded or the
    /// group has none — the card then carries the name alone.
    private func icon() -> UIImage? {
        sessionContainer.profileAvatars
            .data(for: .chat(conversationID))
            .flatMap(UIImage.init(data:))
    }

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 0) {
                header

                // A List (not a ScrollView of Buttons) so a drag over a row scrolls and never
                // toggles it on release.
                List {
                    shareTiles
                        .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)

                    Section {
                        ForEach(recentChats) { chat in
                            InviteChatRow(
                                conversation: chat,
                                isSelected: model.isSelected(chat.id)
                            ) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    model.toggleSelection(chat.id)
                                }
                            }
                            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    } header: {
                        sectionHeader
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .safeAreaInset(edge: .bottom) {
            if model.showsComposer {
                composer
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .presentationDetents([.large])
        .presentationBackground(Color.backgroundMain)
        .interactiveDismissDisabled(model.isSending)
        .task {
            // Idempotent: the store returns without a round trip once the bytes are in memory or
            // on disk. Loading here rather than relying on the presenting screen keeps the preview
            // card's icon independent of which screen opened the sheet.
            await sessionContainer.profileAvatars.load(.chat(conversationID), picture: conversation?.picture)
        }
    }

    /// The sheet's own title bar: a centred title and a glass close button on the right.
    private var header: some View {
        ZStack {
            Text("Invite People")
                .font(.appBarButton)
                .foregroundStyle(Color.textMain)

            HStack {
                Spacer()
                CloseButton(style: .glass, binding: $isPresented)
                    .disabled(model.isSending)
            }
        }
        .padding(16)
    }

    /// Share and Copy Invite Link, as the profile's action buttons, laid out as the profile lays
    /// out its own: fixed columns side by side, centred.
    private var shareTiles: some View {
        HStack(alignment: .top, spacing: 0) {
            ProfileActionButton(title: "Share") {
                Image.asset(.shareOS)
                    .renderingMode(.template)
            } action: {
                Analytics.groupInviteShared(method: .share)
                ShareSheet.present(
                    activityItem: GroupInviteShareItem(url: model.url, title: title, icon: icon())
                ) { _ in }
            }
            .accessibilityIdentifier("group-invite-send")

            ProfileActionButton(title: didCopy ? "Copied" : "Copy Invite Link") {
                if didCopy {
                    Image.system(.circleCheck)
                } else {
                    Image.asset(.squareBehindSquare)
                        .renderingMode(.template)
                }
            } action: {
                copy()
            }
            .accessibilityIdentifier("group-invite-copy")
        }
        .frame(maxWidth: .infinity)
    }

    private var sectionHeader: some View {
        Text("Recent Chats")
            .font(.appTextSmall)
            .foregroundStyle(Color.textMain.opacity(0.5))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 16)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.rowSeparator)
                    .frame(height: 1)
            }
            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
            .background(Color.backgroundMain)
    }

    /// The message field and Invite button, shown once a chat is picked (Figma: "Bottom bar pops up
    /// after selecting someone").
    private var composer: some View {
        HStack(spacing: 8) {
            TextField("Add a message", text: $model.message, axis: .vertical)
                .font(.default(size: 17, weight: .medium))
                .foregroundStyle(Color.textMain)
                .lineLimit(1...4)
                .focused($isMessageFocused)
                .disabled(model.isSending)
                .accessibilityIdentifier("group-invite-message")

            Button(action: invite) {
                ZStack {
                    Text("Invite").opacity(model.isSending ? 0 : 1)
                    if model.isSending {
                        ProgressView().tint(Color.textAction)
                    }
                }
                .font(.default(size: 17, weight: .medium))
                .foregroundStyle(Color.textAction)
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(Color.action, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(model.isSending)
            .accessibilityIdentifier("group-invite-submit")
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .modifier(ComposerGlass())
        .padding(.horizontal, 22)
        .padding(.bottom, 8)
    }

    private func invite() {
        isMessageFocused = false
        Task {
            guard let first = await model.sendInvites(via: { text, chatID in
                await conversationController.send(text, to: chatID)
            }) else { return }
            isPresented = false
            onInvited(first)
        }
    }

    private func copy() {
        Analytics.groupInviteShared(method: .theCopy)
        UIPasteboard.general.string = model.url.absoluteString
        withAnimation(.easeInOut(duration: 0.15)) {
            didCopy = true
        }
        Task {
            try? await Task.sleep(for: Self.confirmationDuration)
            withAnimation(.easeInOut(duration: 0.15)) {
                didCopy = false
            }
        }
    }
}

/// One recent chat: its picture and name, and a check that fills when picked.
private struct InviteChatRow: View {

    let conversation: Conversation
    let isSelected: Bool
    let onToggle: () -> Void

    @Environment(ConversationController.self) private var conversationController
    @Environment(SessionContainer.self) private var sessionContainer

    private var counterpart: ConversationMember? {
        conversation.counterpart(excluding: conversationController.selfUserID)
    }

    /// The chat itself for a group, the counterpart for a DM — as the Chats tab's row does.
    private var avatarSubject: ProfileAvatarStore.AvatarSubject {
        guard conversation.type != .group, let userID = counterpart?.userID else { return .chat(conversation.id) }
        return .user(userID)
    }

    private var avatarPicture: ProfilePicture? {
        conversation.type == .group ? conversation.picture : counterpart?.profilePicture
    }

    private var avatarID: String {
        conversation.type == .group
            ? conversation.id.description
            : (counterpart?.userID?.uuidString ?? conversation.id.description)
    }

    var body: some View {
        let name = conversationController.displayName(for: conversation)

        Button(action: onToggle) {
            HStack(spacing: 16) {
                ContactAvatarView(
                    id: avatarID,
                    displayName: name,
                    imageData: sessionContainer.profileAvatars.data(for: avatarSubject),
                    blurhash: avatarPicture?.thumbnailBlurhash,
                    size: 24
                )

                HStack {
                    Text(name)
                        .font(.default(size: 17, weight: .bold))
                        .foregroundStyle(Color.textMain)
                        .lineLimit(1)

                    Spacer(minLength: 12)

                    CheckView(active: isSelected)
                }
                .padding(.vertical, 16)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color.rowSeparator)
                        .frame(height: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("group-invite-chat-row")
        .task(id: avatarSubject) {
            await sessionContainer.profileAvatars.load(avatarSubject, picture: avatarPicture)
        }
    }
}

/// The composer's translucent shell: Liquid Glass where the OS has it.
private struct ComposerGlass: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content.background(.ultraThinMaterial, in: shape)
        }
    }
}
