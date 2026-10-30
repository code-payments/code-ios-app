//
//  InvitePeopleSheet.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import UIKit
import FlipcashUI
import FlipcashCore

/// Which of a private group's two links the host's link card hands out.
enum InviteCardLink: Equatable {
    /// The current invite link: whoever opens it joins right away.
    case invite
    /// The plain `/chat/{uuid}` link: whoever opens it asks to join.
    case plain
}

/// Invite People for a viewer with `can_invite` (surface 1, frames 1m, 1m′, 1m″, node 13137:203):
/// one link card, the Approve new members switch that picks its link, and Manage Invites.
///
/// Opening it makes nothing (Decision 9). The first Share Link, Copy Link or Show Group Card makes
/// the current link when there is none, with the pill on "Creating link…" until it returns.
private struct InviteLinkCardSheet: View {

    /// What the host picked that needs the sheet gone first.
    enum Choice {
        case share(InviteCardLink)
        case groupCard(GroupCardScreen.Card)
        case manageInvites
    }

    private enum Tap {
        case share
        case copy
        case groupCard
    }

    let conversationID: ConversationID
    let links: GroupInviteLinks
    /// Called as the sheet starts dismissing, so the presenter runs the choice on dismissal.
    let onChoose: (Choice) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(ConversationController.self) private var conversationController
    @Environment(SessionContainer.self) private var sessionContainer

    @State private var dialogItem: DialogItem?
    @State private var didCopy = false

    private var conversation: Conversation? {
        conversationController.conversation(withID: conversationID)
    }

    private var isApproving: Bool {
        sessionContainer.approveNewMembers.isOn(for: conversationID)
    }

    private var approvingBinding: Binding<Bool> {
        Binding {
            isApproving
        } set: {
            sessionContainer.approveNewMembers.set($0, for: conversationID)
        }
    }

    private var pill: InviteLinkCard.Pill {
        if didCopy { return .copied }
        if isApproving { return .link(.groupChatInvite(for: conversationID)) }
        if links.isCreating { return .creating }
        if let url = links.current?.url { return .link(url) }
        switch links.loadState {
        case .idle, .loading: return .loading
        case .loaded, .failed: return .empty
        }
    }

    private var caption: String? {
        if isApproving { return InviteLinkCopy.plainLinkCaption }
        return links.current.map { InviteLinkCopy.cardCaption($0.invite) }
    }

    var body: some View {
        PartialSheet {
            InviteLinkCard(
                title: InviteLinkCopy.sheetTitle(groupName: conversation?.title ?? ""),
                pill: pill,
                caption: caption,
                isCreating: links.isCreating,
                canRevoke: !isApproving && links.current != nil,
                isApproving: approvingBinding,
                onShare: { run(.share) },
                onCopy: { run(.copy) },
                onShowGroupCard: { run(.groupCard) },
                onRevoke: confirmRevoke,
                onManageInvites: { choose(.manageInvites) }
            )
        }
        .dialog(item: $dialogItem)
    }

    // MARK: - Actions -

    /// Runs a tap on the card's link, making the current invite link first when there is none.
    private func run(_ tap: Tap) {
        if isApproving {
            finish(tap, link: .plain)
            return
        }
        guard !links.isCreating else { return }
        Task {
            do {
                _ = try await links.currentLink()
                finish(tap, link: .invite)
            } catch {
                dialogItem = InviteLinkDialogs.createFailed(
                    error,
                    onManage: { choose(.manageInvites) },
                    // Frame 1e: invite links aren't available yet, so the card moves to the plain link.
                    onShareGroupLink: { approvingBinding.wrappedValue = true }
                )
            }
        }
    }

    private func finish(_ tap: Tap, link: InviteCardLink) {
        switch tap {
        case .share:
            choose(.share(link))
        case .copy:
            copy(link)
        case .groupCard:
            guard let card = groupCard(link) else { return }
            choose(.groupCard(card))
        }
    }

    private func choose(_ choice: Choice) {
        dismiss()
        onChoose(choice)
    }

    private func copy(_ link: InviteCardLink) {
        let url: URL?
        switch link {
        case .invite: url = links.current?.url
        case .plain: url = .groupChatInvite(for: conversationID)
        }
        guard let url else { return }
        Analytics.groupInviteShared(method: .theCopy)
        UIPasteboard.general.string = url.absoluteString
        withAnimation(.easeInOut(duration: 0.15)) { didCopy = true }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(.easeInOut(duration: 0.15)) { didCopy = false }
        }
    }

    private func groupCard(_ link: InviteCardLink) -> GroupCardScreen.Card? {
        let cardLink: GroupCardScreen.Card.Link
        switch link {
        case .invite:
            guard let entry = links.current, let url = entry.url else { return nil }
            cardLink = .invite(url, expiresAt: entry.invite.expiresAt)
        case .plain:
            cardLink = .plain
        }
        return GroupCardScreen.Card(
            id: conversationID,
            conversation: conversation,
            avatar: sessionContainer.profileAvatars.data(for: .chat(conversationID)),
            link: cardLink
        )
    }

    /// Revoke and Make New Link: Manage Invites' confirmation, then the card stays empty until the
    /// next tap makes a new current link.
    private func confirmRevoke() {
        guard let current = links.current else { return }
        dialogItem = InviteLinkDialogs.revoke {
            Task {
                do {
                    try await links.revoke(current)
                } catch {
                    dialogItem = .error(title: "Something Went Wrong", subtitle: "Please try again")
                }
            }
        }
    }
}

/// Frames 1m, 1m′ and 1m″ as plain state, for the sheet and its previews.
struct InviteLinkCard: View {

    enum Pill: Equatable {
        /// The first `GetChatInvites` is in flight.
        case loading
        /// `CreateInvite` is in flight.
        case creating
        /// No current link, and none made yet.
        case empty
        /// Copy Link just ran.
        case copied
        case link(URL)
    }

    let title: String
    let pill: Pill
    let caption: String?
    let isCreating: Bool
    /// Whether the ⋯ menu offers Revoke and Make New Link: an invite link only.
    let canRevoke: Bool
    @Binding var isApproving: Bool
    let onShare: () -> Void
    let onCopy: () -> Void
    let onShowGroupCard: () -> Void
    let onRevoke: () -> Void
    let onManageInvites: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.appTextLarge)
                .foregroundStyle(Color.textMain)
                .lineLimit(1)
                .padding(.horizontal, 4)
                .padding(.bottom, 8)

            linkCard
            approveRow

            ActionCardRow(
                icon: Image(systemName: "list.bullet"),
                title: "Manage Invites",
                subtitle: "Make more links with an expiry or a use limit",
                identifier: "invite-people-manage",
                action: onManageInvites
            )
        }
        .padding(.horizontal)
        .padding(.vertical, 20)
    }

    private var linkCard: some View {
        VStack(spacing: 12) {
            pillView

            CodeButton(isLoading: isCreating, style: .filled, title: "Share Link", action: onShare)
                .accessibilityIdentifier("invite-card-share")

            if let caption {
                Text(caption)
                    .font(.appTextCaption)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("invite-card-caption")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var pillView: some View {
        HStack(spacing: 8) {
            pillText
                .font(.default(size: 14, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("invite-card-pill")

            Menu {
                Button("Copy Link", action: onCopy)
                Button("Show Group Card", action: onShowGroupCard)
                if canRevoke {
                    Button("Revoke and Make New Link", role: .destructive, action: onRevoke)
                }
            } label: {
                Image.system(.ellipsis)
                    .font(.default(size: 14, weight: .bold))
                    .foregroundStyle(Color.textMain)
                    .frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.1), in: Circle())
            }
            .disabled(isCreating)
            .accessibilityLabel("More")
            .accessibilityIdentifier("invite-card-more")
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .frame(height: 48)
        .background(Color.white.opacity(0.08), in: Capsule())
    }

    @ViewBuilder
    private var pillText: some View {
        switch pill {
        case .loading:
            ProgressView()
                .tint(Color.textMain)
        case .creating:
            Text(InviteLinkCopy.creating)
                .foregroundStyle(Color.textSecondary)
        case .empty:
            Text(InviteLinkCopy.noLinkYet)
                .foregroundStyle(Color.textSecondary)
        case .copied:
            Text("Copied")
                .foregroundStyle(Color.textMain)
        case .link(let url):
            Text(InviteLinkPanel.display(url))
                .foregroundStyle(Color.textMain)
        }
    }

    private var approveRow: some View {
        Toggle(isOn: $isApproving) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Approve new members")
                    .font(.appTextMedium)
                    .foregroundStyle(Color.textMain)
                Text(InviteLinkCopy.approveSubtitle(isOn: isApproving))
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textSecondary)
            }
            .multilineTextAlignment(.leading)
        }
        .tint(.success)
        .padding(20)
        .background(Color.white.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityIdentifier("invite-card-approve")
    }
}

/// Presents Invite People and whatever its link card picks, once the card's sheet has gone.
private struct InvitePeoplePresenter: ViewModifier {

    let conversationID: ConversationID
    let canInvite: Bool
    @Binding var isPresented: Bool
    let onManageInvites: () -> Void
    let onInvited: (ConversationID) -> Void

    private enum Share: Identifiable {
        case invite(GroupInviteLinks)
        case join
        var id: String {
            switch self {
            case .invite: "invite"
            case .join: "join"
            }
        }
    }

    /// The group card shown from the link card's ⋯ menu.
    private struct CardItem: Identifiable {
        let id = UUID()
        let card: GroupCardScreen.Card
    }

    @Environment(SessionContainer.self) private var sessionContainer

    @State private var links: GroupInviteLinks?
    /// The link card's choice, run once its sheet has gone so the next one can present.
    @State private var pendingChoice: InviteLinkCardSheet.Choice?
    @State private var share: Share?
    @State private var groupCard: CardItem?

    func body(content: Content) -> some View {
        content
            .task(id: canInvite) {
                guard canInvite, links == nil else { return }
                links = GroupInviteLinks(conversationID: conversationID, service: sessionContainer.inviteLinks)
            }
            .sheet(isPresented: canInvite ? $isPresented : .constant(false), onDismiss: runPendingChoice) {
                if let links {
                    InviteLinkCardSheet(conversationID: conversationID, links: links) { pendingChoice = $0 }
                        // Reads which link is current; makes nothing.
                        .task { try? await links.load() }
                }
            }
            .fullScreenCover(isPresented: canInvite ? .constant(false) : $isPresented) {
                ShareToChatsSheet(subject: .group(conversationID), isPresented: $isPresented, onInvited: onInvited)
            }
            .fullScreenCover(item: $share) { share in
                switch share {
                case .invite(let links):
                    ShareToChatsSheet(subject: .inviteLink(conversationID, links), isPresented: isSharing, onInvited: invited)
                case .join:
                    ShareToChatsSheet(subject: .group(conversationID), isPresented: isSharing, onInvited: invited)
                }
            }
            .fullScreenCover(item: $groupCard) { item in
                GroupCardScreen(card: item.card) { withoutAnimation { groupCard = nil } }
                    // The card fades itself in over the screen, as it does over the share sheet.
                    .presentationBackground(.clear)
            }
    }

    private var isSharing: Binding<Bool> {
        Binding { share != nil } set: { if !$0 { share = nil } }
    }

    private func runPendingChoice() {
        guard let choice = pendingChoice else { return }
        pendingChoice = nil
        switch choice {
        case .share(.invite):
            guard let links else { return }
            share = .invite(links)
        case .share(.plain):
            share = .join
        case .groupCard(let card):
            withoutAnimation { groupCard = CardItem(card: card) }
        case .manageInvites:
            onManageInvites()
        }
    }

    private func withoutAnimation(_ change: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, change)
    }

    private func invited(_ chatID: ConversationID) {
        share = nil
        onInvited(chatID)
    }
}

extension View {

    /// Invite People for a group: the link card for a viewer with `can_invite`, and the plain
    /// link's share sheet for everyone else, as before invite links.
    func invitePeople(
        _ conversationID: ConversationID,
        canInvite: Bool,
        isPresented: Binding<Bool>,
        onManageInvites: @escaping () -> Void,
        onInvited: @escaping (ConversationID) -> Void
    ) -> some View {
        modifier(InvitePeoplePresenter(
            conversationID: conversationID,
            canInvite: canInvite,
            isPresented: isPresented,
            onManageInvites: onManageInvites,
            onInvited: onInvited
        ))
    }
}

// MARK: - Previews -

private let previewURL = URL(string: "https://app.flipcash.com/chat/invite#s=kQ3vR8mZp4LwN2yTb7cXe1aFhJ6sDg0uVq5oIrKxT9a")!
private let previewPlainURL = URL(string: "https://app.flipcash.com/chat/52fba6a9-3940-899e-af16-eddf7c6364b2")!

#Preview("1m · Approve new members") {
    @Previewable @State var isApproving = false
    Background(color: .backgroundMain) {
        VStack {
            Spacer()
            InviteLinkCard(
                title: "Invite to Moony",
                pill: .link(isApproving ? previewPlainURL : previewURL),
                caption: isApproving ? InviteLinkCopy.plainLinkCaption : "0 joined · Expires Nov 3",
                isCreating: false,
                canRevoke: !isApproving,
                isApproving: $isApproving,
                onShare: {}, onCopy: {}, onShowGroupCard: {}, onRevoke: {}, onManageInvites: {}
            )
            .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .padding(8)
        }
    }
}

#Preview("1b · Creating link") {
    Background(color: .backgroundMain) {
        VStack {
            Spacer()
            InviteLinkCard(
                title: "Invite to Moony",
                pill: .creating,
                caption: nil,
                isCreating: true,
                canRevoke: false,
                isApproving: .constant(false),
                onShare: {}, onCopy: {}, onShowGroupCard: {}, onRevoke: {}, onManageInvites: {}
            )
            .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .padding(8)
        }
    }
}
