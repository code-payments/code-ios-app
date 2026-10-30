//
//  ShareToChatsSheet.swift
//  Flipcash
//

import SwiftUI
import UIKit
import FlipcashCore
import FlipcashUI

/// What ``ShareToChatsSheet`` hands out.
enum ShareToChatsSubject {
    /// A group's invite link. A group is not discoverable — the link built from its id is the only
    /// way in.
    case group(ConversationID)
    /// A private group's invite link, for a viewer with `can_invite` (surface 1). The link carries
    /// the group's secret, so only E2EE chats are offered (Decision 6). Its group card encodes the
    /// invite link, so whoever scans it joins without approval.
    /// `links` makes the link when the tap that opened the sheet found none. `entry` picks one of the
    /// viewer's active links, as Manage Invites does; nil means the current one.
    case inviteLink(ConversationID, GroupInviteLinks, entry: InviteID? = nil)
    /// A person's public profile link, the one their own You tab shares. `preview` is the tip-code
    /// image for the system share sheet's card, when one is rendered. `directChatID` is the viewer's
    /// DM with them, left out of the picker so nobody is sent their own profile.
    case user(
        userID: UserID,
        username: Username?,
        displayName: String?,
        preview: TipCodePreview? = nil,
        directChatID: ConversationID?
    )
    /// A link to one message, `/chat/{chatId}/m/{seq}`. The recipient's app draws the message card
    /// from it, so the link is all that goes out.
    case message(URL)
    /// A currency's public page, the link the Currency Info share button has always handed out.
    case currency(url: URL, name: String)
}

/// "Invite People" (nodes 10330:19387, 10330:19549, 10329:12104): hand out a link by Share or Copy,
/// or post it straight into recent chats with an optional message. A group's sheet shows its link in
/// a pill above the tiles, whichever link it is. A group gets a third tile, Show QR Code, and a
/// person with a name gets Show Profile Card; either draws its card over the sheet, and closing it
/// uncovers the sheet as it was left.
struct ShareToChatsSheet: View {

    let subject: ShareToChatsSubject

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
    @State private var isShowingCard = false
    @State private var isShowingGroupCard = false
    @FocusState private var isMessageFocused: Bool

    init(
        subject: ShareToChatsSubject,
        isPresented: Binding<Bool>,
        onInvited: @escaping (ConversationID) -> Void
    ) {
        self.subject = subject
        self._isPresented = isPresented
        self.onInvited = onInvited
        let url: URL = switch subject {
        case .group(let id): .groupChatInvite(for: id)
        // Stands in until the link exists; Copy, Share and Invite read the link itself.
        case .inviteLink(let id, let links, let entry): Self.inviteEntry(links, entry)?.url ?? .groupChatInvite(for: id)
        case .user(let userID, let username, _, _, _): .tipcard(for: userID, username: username)
        case .message(let url): url
        case .currency(let url, _): url
        }
        self._model = State(initialValue: InvitePeopleViewModel(url: url))
    }

    /// The group being invited to, nil when sharing a person.
    private var groupID: ConversationID? {
        switch subject {
        case .group(let id), .inviteLink(let id, _, _): id
        case .user, .message, .currency: nil
        }
    }

    /// The chat the picker leaves out: the group itself, or the DM with the person shared.
    private var excludedChatID: ConversationID? {
        switch subject {
        case .group(let id), .inviteLink(let id, _, _): id
        case .user(_, _, _, _, let directChatID): directChatID
        // The message's own chat stays: a link sent there points at something further up.
        case .message, .currency: nil
        }
    }

    /// The person whose card Show Profile Card draws. Nil for a group, and for a person with no
    /// display name, who has no card.
    private var card: ProfileCardScreen.Card? {
        switch subject {
        case .group, .inviteLink, .message, .currency:
            return nil
        case .user(let userID, let username, let displayName, _, _):
            guard let displayName, !displayName.isEmpty else { return nil }
            return ProfileCardScreen.Card(userID: userID, displayName: displayName, username: username)
        }
    }

    /// Whether the sheet offers the group card tile: for every group subject, plain or invite link,
    /// and for nothing else.
    nonisolated static func showsGroupCardTile(for subject: ShareToChatsSubject) -> Bool {
        switch subject {
        case .group, .inviteLink: true
        case .user, .message, .currency: false
        }
    }

    /// The group card's content, from the conversation this sheet's host already holds. It encodes
    /// this sheet's link; nil while an invite link is still being made.
    private var groupCard: GroupCardScreen.Card? {
        let link: GroupCardScreen.Card.Link
        switch subject {
        case .group:
            link = .plain
        case .inviteLink:
            guard let entry = inviteEntry, let url = entry.url else { return nil }
            link = .invite(url, expiresAt: entry.invite.expiresAt)
        case .user, .message, .currency:
            return nil
        }
        guard let groupID else { return nil }
        return GroupCardScreen.Card(
            id: groupID,
            conversation: conversation,
            avatar: sessionContainer.profileAvatars.data(for: .chat(groupID)),
            link: link
        )
    }

    /// The invite links behind an invite-link subject.
    private var inviteLinks: GroupInviteLinks? {
        guard case .inviteLink(_, let links, _) = subject else { return nil }
        return links
    }

    /// The link this sheet hands out: the chosen entry, or the current link.
    private var inviteEntry: GroupInviteLinks.Entry? {
        guard case .inviteLink(_, let links, let entry) = subject else { return nil }
        return Self.inviteEntry(links, entry)
    }

    private static func inviteEntry(_ links: GroupInviteLinks, _ id: InviteID?) -> GroupInviteLinks.Entry? {
        guard let id else { return links.current }
        return links.active.first { $0.id == id }
    }

    private var isInviteMode: Bool {
        inviteLinks != nil
    }

    /// The invite link once it exists. Nil while the tap that opened the sheet is making it.
    private var inviteURL: URL? {
        inviteEntry?.url
    }

    /// Whether Share, Copy and Invite have a link to hand out yet.
    private var hasLink: Bool {
        !isInviteMode || inviteURL != nil
    }

    private var sheetTitle: String {
        switch subject {
        case .group, .inviteLink: "Invite People"
        case .user: "Share Profile"
        case .message: "Share Message"
        case .currency(_, let name): "Share \(name)"
        }
    }

    private var copyTitle: String {
        switch subject {
        case .group, .inviteLink: "Copy Invite Link"
        case .user, .message, .currency: "Copy Link"
        }
    }

    private var sendTitle: String {
        switch subject {
        case .group, .inviteLink: "Invite"
        case .user, .message, .currency: "Send"
        }
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
        groupID.flatMap(conversationController.conversation(withID:))
    }

    /// The chats the Chats tab lists, newest activity first: 1:1 chats and joined groups, less
    /// ``excludedChatID``. Search and people outside recent chats are out of scope.
    ///
    /// An invite link goes only to chats the server can't read (Decision 6): the link and the
    /// server's records together open the group key.
    private var recentChats: [Conversation] {
        let chats = conversationController.chatListConversations.filter { $0.id != excludedChatID }
        guard isInviteMode else { return chats }
        return chats.filter(E2eePolicy.shouldEncrypt)
    }

    /// The group's picture for the share sheet's own preview card.
    ///
    /// Decoded at the tap rather than in a computed property, so a thumbnail isn't re-decoded on
    /// every render of a sheet that shows it nowhere. Nil while the avatar hasn't loaded or the
    /// group has none — the card then carries the name alone.
    private func icon() -> UIImage? {
        groupID
            .flatMap { sessionContainer.profileAvatars.data(for: .chat($0)) }
            .flatMap(UIImage.init(data:))
    }

    /// What Share hands the system share sheet: the group's preview card, the person's, or a message's bare link.
    private func shareItems() -> [Any] {
        switch subject {
        case .group:
            [GroupInviteShareItem(url: model.url, title: title, icon: icon())]
        case .inviteLink:
            inviteURL.map { [GroupInviteShareItem(url: $0, title: title, icon: icon(), kind: .inviteLink)] } ?? []
        case .user(_, _, let displayName, let preview, _):
            [TipCodeShareItem.profile(url: model.url, displayName: displayName, preview: preview)]
        case .message, .currency:
            // The URL itself, not an item source: the system builds the preview card from the link
            // rather than from a group invite's fallback title.
            [model.url]
        }
    }

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 0) {
                // A List (not a ScrollView of Buttons) so a drag over a row scrolls and never
                // toggles it on release.
                List {
                    Group {
                        if groupID != nil {
                            VStack(spacing: 16) {
                                linkPanel
                                shareTiles
                            }
                        } else {
                            shareTiles
                        }
                    }
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
                        // Frame 1b: nothing to send until the link exists.
                        .disabled(!hasLink)
                        .opacity(hasLink ? 1 : 0.4)
                        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }

                    if isInviteMode {
                        Text(InviteLinkCopy.footnote)
                            .font(.default(size: 12, weight: .medium))
                            .foregroundStyle(Color.textMain.opacity(0.5))
                            .fixedSize(horizontal: false, vertical: true)
                            .listRowInsets(EdgeInsets(top: 16, leading: 20, bottom: 16, trailing: 20))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .accessibilityIdentifier("invite-link-footnote")
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
        .overlay {
            if isShowingCard, let card {
                ProfileCardScreen(card: card) {
                    withAnimation(ProfileCardScreen.fade) { isShowingCard = false }
                }
                .transition(.asymmetric(insertion: .identity, removal: .opacity))
            } else if isShowingGroupCard, let groupCard {
                GroupCardScreen(card: groupCard) {
                    withAnimation(GroupCardScreen.fade) { isShowingGroupCard = false }
                }
                .transition(.asymmetric(insertion: .identity, removal: .opacity))
            }
        }
        .presentationBackground(Color.backgroundMain)
        .interactiveDismissDisabled(model.isSending)
        .task {
            // Idempotent: the store returns without a round trip once the bytes are in memory or
            // on disk. Loading here rather than relying on the presenting screen keeps the preview
            // card's icon independent of which screen opened the sheet.
            guard let groupID else { return }
            await sessionContainer.profileAvatars.load(.chat(groupID), picture: conversation?.picture)
        }
    }

    /// The sheet's own title bar: a centred title and a glass close button on the right.
    private var header: some View {
        ZStack {
            Text(sheetTitle)
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

    /// Share and Copy Invite Link, plus Show QR Code for a group or Show Profile Card for a person
    /// with a card, as tiles side by side, sized to the tallest.
    private var shareTiles: some View {
        HStack(spacing: 10) {
            ShareTile(title: "Share") {
                Image.asset(.shareOS)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
            } action: {
                if groupID != nil { Analytics.groupInviteShared(method: .share) }
                ShareSheet.present(activityItems: shareItems()) { _ in }
            }
            .disabled(!hasLink)
            .opacity(hasLink ? 1 : 0.35)
            .accessibilityIdentifier("group-invite-send")

            ShareTile(title: didCopy ? "Copied" : copyTitle) {
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
            .disabled(!hasLink)
            .opacity(hasLink ? 1 : 0.35)
            .accessibilityIdentifier("group-invite-copy")

            if card != nil {
                ShareTile(title: "Show Profile Card") {
                    // The Scan tab's outline glyph: the card is what the scanner reads.
                    Image(HomeTab.scan.iconName(isSelected: false))
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                } action: {
                    isMessageFocused = false
                    // The card runs its own reveal on appear, so only its removal is animated.
                    isShowingCard = true
                }
                .accessibilityIdentifier("profile-card-tile")
            }

            if Self.showsGroupCardTile(for: subject) {
                ShareTile(title: "Show QR Code") {
                    Image(HomeTab.scan.iconName(isSelected: false))
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                } action: {
                    isMessageFocused = false
                    isShowingGroupCard = true
                }
                .disabled(!hasLink)
                .opacity(hasLink ? 1 : 0.35)
                .accessibilityIdentifier("group-card-tile")
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var sectionHeader: some View {
        Text("Recent Chats")
            .font(.default(size: 14, weight: .bold))
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
                    Text(sendTitle).opacity(model.isSending ? 0 : 1)
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
            .disabled(model.isSending || !hasLink)
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

            Text(sendTitle)
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

    // MARK: - Invite link -

    /// The group's link over the tiles: the invite link with its expiry and uses, or the plain link,
    /// which has neither.
    private var linkPanel: some View {
        InviteLinkPanel(
            pill: isInviteMode ? inviteURL.map(InviteLinkPanel.Pill.link) ?? .creating : .link(model.url),
            meta: inviteEntry.map { InviteLinkCopy.sheetMeta($0.invite) }
        )
    }

    private func invite() {
        isMessageFocused = false
        Task {
            if isInviteMode {
                guard let inviteURL else { return }
                model.url = inviteURL
            }
            guard let first = await model.sendInvites(via: { text, chatID in
                await conversationController.send(text, to: chatID)
            }) else { return }
            isPresented = false
            onInvited(first)
        }
    }

    private func copy() {
        if groupID != nil { Analytics.groupInviteShared(method: .theCopy) }
        UIPasteboard.general.string = (inviteURL ?? model.url).absoluteString
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
                    .font(.default(size: 14, weight: .bold))
                    .opacity(0.5)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Color.textMain)
            .padding(.horizontal, 8)
            // Fills the row's height, so a tile whose title wraps doesn't stand taller than the rest.
            .frame(maxWidth: .infinity, minHeight: 95, maxHeight: .infinity)
            .background(Color.backgroundRow)
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

                    if isSelected {
                        RadioButton(isSelected: true)
                    } else {
                        // The design's unselected ring: 2pt at 20% white, where RadioButton draws 1pt white.
                        Circle()
                            .strokeBorder(Color.white.opacity(0.2), lineWidth: 2)
                            .frame(width: 24, height: 24)
                            .accessibilityHidden(true)
                    }
                }
                .frame(height: 52)
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
