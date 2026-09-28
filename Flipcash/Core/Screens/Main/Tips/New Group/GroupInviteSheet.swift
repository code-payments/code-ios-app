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

    /// How far the composer slides from: past the home indicator, off the sheet.
    private static let composerDrop: CGFloat = 120

    @State private var model: InvitePeopleViewModel
    @State private var didCopy = false
    @State private var headerHeight: CGFloat = 0
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
                // A List (not a ScrollView of Buttons) so a drag over a row scrolls and never
                // toggles it on release.
                List {
                    shareTiles
                        .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)

                    // A row rather than a section header, which a plain List pins to the top.
                    sectionHeader
                        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)

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
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .softScrollEdge(for: [.top, .bottom])
                .bar(edge: .top) {
                    header
                }
                // The edge effect draws only under a bar with drawn content, and drops out while that
                // content moves. So the bar holds a still, invisible copy of the field, pick or no
                // pick, and the real field slides over it from outside the bar.
                .bar(edge: .bottom) {
                    composerStandIn
                }
                .overlay(alignment: .bottom) {
                    ZStack {
                        if model.showsComposer {
                            composer
                                // Slides rather than fades: Liquid Glass switches partway through an
                                // opacity change instead of following it.
                                .transition(.offset(y: Self.composerDrop))
                        }
                    }
                    .animation(.spring(duration: 0.35), value: model.showsComposer)
                }
                // Down to the screen edge, so the bottom blur spans the same height as the top one
                // rather than the field plus the home indicator.
                .ignoresSafeArea(.container, edges: .bottom)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
        .onGeometryChange(for: CGFloat.self, of: \.size.height) { headerHeight = $0 }
    }

    /// Share and Copy Invite Link as two tiles side by side, sized to the taller of the two.
    private var shareTiles: some View {
        HStack(spacing: 10) {
            ShareTile(title: "Share") {
                Image.asset(.shareOS)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
            } action: {
                Analytics.groupInviteShared(method: .share)
                ShareSheet.present(
                    activityItem: GroupInviteShareItem(url: model.url, title: title, icon: icon())
                ) { _ in }
            }
            .accessibilityIdentifier("group-invite-send")

            ShareTile(title: didCopy ? "Copied" : "Copy Invite Link") {
                if didCopy {
                    Image.system(.circleCheck)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image.asset(.squareBehindSquare)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                }
            } action: {
                copy()
            }
            .accessibilityIdentifier("group-invite-copy")
        }
        .fixedSize(horizontal: false, vertical: true)
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
    }

    /// The message field and Invite button, shown once a chat is picked (Figma: "Bottom bar pops up
    /// after selecting someone"). Built as the chat composer is: the button sits inside one glass
    /// field that floats over the list.
    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Add a message", text: $model.message, axis: .vertical)
                .font(.appTextMessage)
                .foregroundStyle(Color.textMain)
                .tint(.white)
                .lineLimit(1...4)
                .focused($isMessageFocused)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: BarMetrics.fieldMinHeight)
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
                .frame(height: BarMetrics.fieldMinHeight)
                .background(Color.action, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(model.isSending)
            .accessibilityIdentifier("group-invite-submit")
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, BarMetrics.fieldVerticalPadding)
        // Behind the field rather than wrapping it, which would break the text-selection grabbers.
        .glassFieldBackground(cornerRadius: BarMetrics.cornerRadius)
        .padding(.horizontal, 12)
        .padding(.top, BarMetrics.contentPadding)
        .padding(.bottom, bottomPadding)
    }

    /// Lifts a one-line field so it and the stand-in fill exactly the header's height from the
    /// screen edge.
    private var bottomPadding: CGFloat {
        let fieldHeight = BarMetrics.contentHeight + BarMetrics.contentPadding
        return max(BarMetrics.contentPadding, headerHeight - fieldHeight)
    }

    /// The composer's shape and size with nothing live in it, drawn invisibly under the bottom bar.
    private var composerStandIn: some View {
        // Mirrors the field's text and button so it grows line for line with the real composer.
        HStack(alignment: .bottom, spacing: 10) {
            Text(model.message.isEmpty ? "Add a message" : model.message)
                .font(.appTextMessage)
                .lineLimit(1...4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: BarMetrics.fieldMinHeight)

            Text("Invite")
                .font(.default(size: 17, weight: .medium))
                .padding(.horizontal, 14)
                .frame(height: BarMetrics.fieldMinHeight)
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, BarMetrics.fieldVerticalPadding)
        .glassFieldBackground(cornerRadius: BarMetrics.cornerRadius)
        .padding(.horizontal, 12)
        .padding(.top, BarMetrics.contentPadding)
        .padding(.bottom, bottomPadding)
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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

/// A share action as a tile (Figma node 10330:19400): a 28pt glyph over a dimmed, centred label
/// that wraps rather than truncates.
private struct ShareTile<Icon: View>: View {

    let title: String
    @ViewBuilder let icon: () -> Icon
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                icon()
                    .frame(width: 28, height: 28)
                Text(title)
                    .font(.appTextSmall)
                    .opacity(0.5)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Color.textMain)
            .padding(.vertical, 16)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 95)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: Metrics.buttonRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Metrics.buttonRadius, style: .continuous))
        }
        .buttonStyle(.plain)
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

private extension View {

    /// Floats `bar` over one edge of the list. On iOS 26+ the bar joins the scroll edge effect, so
    /// rows blur progressively beneath it as they do under a navigation bar or the chat composer.
    @ViewBuilder
    func bar(edge: VerticalEdge, @ViewBuilder _ bar: () -> some View) -> some View {
        if #available(iOS 26.0, *) {
            safeAreaBar(edge: edge, spacing: 0, content: bar)
        } else {
            safeAreaInset(edge: edge, spacing: 0, content: bar)
        }
    }
}
