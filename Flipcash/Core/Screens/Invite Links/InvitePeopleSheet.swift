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

/// Invite People for a viewer with `can_invite` (surface 1, frames 1m and 1m′, node 13137:203):
/// one link card, the Approve New Members switch that picks its link, and Manage Invites.
///
/// Opening it makes nothing (Decision 9). The first Share Link makes the current link when there is
/// none, with the pill on "Creating link…" until it returns. Copy Link and Show QR Code are on the
/// Invite People sheet Share Link opens; revoking is done in Manage Invites.
private struct InviteLinkCardSheet: View {

    /// What the host picked that needs the sheet gone first.
    enum Choice {
        case share(InviteCardLink)
        case manageInvites
    }

    let conversationID: ConversationID
    let links: GroupInviteLinks
    /// Called as the sheet starts dismissing, so the presenter runs the choice on dismissal.
    let onChoose: (Choice) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(ConversationController.self) private var conversationController
    @Environment(SessionContainer.self) private var sessionContainer

    @State private var dialogItem: DialogItem?

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
                isApproving: approvingBinding,
                onShare: share,
                onManageInvites: { choose(.manageInvites) },
                onClose: { dismiss() }
            )
            // PartialSheet sizes to what it measures, so a card squeezed on first layout
            // would keep its truncated subtitles; take the card's full height instead.
            .fixedSize(horizontal: false, vertical: true)
        }
        .dialog(item: $dialogItem)
    }

    // MARK: - Actions -

    /// Share Link, making the current invite link first when there is none.
    private func share() {
        if isApproving {
            choose(.share(.plain))
            return
        }
        guard !links.isCreating else { return }
        Task {
            do {
                _ = try await links.currentLink()
                choose(.share(.invite))
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

    private func choose(_ choice: Choice) {
        dismiss()
        onChoose(choice)
    }
}

/// Frames 1m and 1m′ as plain state, for the sheet and its previews.
struct InviteLinkCard: View {

    enum Pill: Equatable {
        /// The first `GetChatInvites` is in flight.
        case loading
        /// `CreateInvite` is in flight.
        case creating
        /// No current link, and none made yet.
        case empty
        case link(URL)
    }

    let title: String
    let pill: Pill
    let caption: String?
    let isCreating: Bool
    @Binding var isApproving: Bool
    let onShare: () -> Void
    let onManageInvites: () -> Void
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Frame 1m's card fill (Link card, Approve New Members, Manage Invites), white 8%.
    private static let cardFill = Color.white.opacity(0.08)
    /// Frame 1m's link pill fill, inside the link card, white 6%.
    private static let pillFill = Color.white.opacity(0.06)
    /// The caption and Approve New Members subtitle. Figma has Inter Regular 13 at white 60%;
    /// Avenir's regular reads much lighter than Inter's, so Medium at 68% matches its weight.
    private static let secondaryFont = Font.default(size: 13, weight: .medium)
    private static let secondaryText = Color.white.opacity(0.68)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
                .padding(.bottom, 8)

            linkCard
            approveRow

            ActionCardRow(
                icon: Image(systemName: "list.bullet"),
                title: "Manage Invites",
                subtitle: "Make more links with an expiry or a use limit",
                identifier: "invite-people-manage",
                fill: Self.cardFill,
                action: onManageInvites
            )
        }
        .padding(.horizontal)
        .padding(.vertical, 20)
        // Approve New Members crossfades the pill, caption and subtitle; any height change rides along.
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: isApproving)
    }

    /// The title centred across the full sheet width, with the E2EE sheet's ✕ on the trailing edge.
    private var header: some View {
        ZStack {
            Text(title)
                .font(.appTextLarge)
                .foregroundStyle(Color.textMain)
                .lineLimit(1)
                // Equal insets on both sides keep the title centred and clear of the ✕.
                .padding(.horizontal, 56)
                .frame(maxWidth: .infinity)

            HStack {
                Spacer()
                CloseButton(style: .glass, action: onClose)
            }
        }
    }

    private var linkCard: some View {
        VStack(spacing: 12) {
            pillView

            CodeButton(isLoading: isCreating, style: .filled, title: "Share Link", action: onShare)
                .accessibilityIdentifier("invite-card-share")

            if let caption {
                Text(caption)
                    .font(Self.secondaryFont)
                    .foregroundStyle(Self.secondaryText)
                    .multilineTextAlignment(.center)
                    .contentTransition(.opacity)
                    .accessibilityIdentifier("invite-card-caption")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Self.cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var pillView: some View {
        pillText
            .contentTransition(.opacity)
            .font(.default(size: 14, weight: .medium))
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("invite-card-pill")
            .padding(.horizontal, 16)
            .frame(height: 48)
        .background(Self.pillFill, in: Capsule())
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
        case .link(let url):
            Text(InviteLinkPanel.display(url))
                .foregroundStyle(Color.textMain)
        }
    }

    private var approveRow: some View {
        Toggle(isOn: $isApproving) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Approve New Members")
                    .font(.appTextMedium)
                    .foregroundStyle(Color.textMain)
                Text(InviteLinkCopy.approveSubtitle(isOn: isApproving))
                    .font(Self.secondaryFont)
                    .foregroundStyle(Self.secondaryText)
                    .contentTransition(.opacity)
            }
            .multilineTextAlignment(.leading)
        }
        .tint(.success)
        .padding(20)
        .background(Self.cardFill)
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

    @Environment(SessionContainer.self) private var sessionContainer

    @State private var links: GroupInviteLinks?
    /// The link card's choice, run once its sheet has gone so the next one can present.
    @State private var pendingChoice: InviteLinkCardSheet.Choice?
    @State private var share: Share?

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
        case .manageInvites:
            onManageInvites()
        }
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

#Preview("1m · Approve New Members") {
    @Previewable @State var isApproving = false
    Background(color: .backgroundMain) {
        VStack {
            Spacer()
            InviteLinkCard(
                title: "Invite to Moony",
                pill: .link(isApproving ? previewPlainURL : previewURL),
                caption: isApproving ? InviteLinkCopy.plainLinkCaption : "0 joined · Expires Nov 3",
                isCreating: false,
                isApproving: $isApproving,
                onShare: {}, onManageInvites: {}, onClose: {}
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
                isApproving: .constant(false),
                onShare: {}, onManageInvites: {}, onClose: {}
            )
            .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .padding(8)
        }
    }
}
