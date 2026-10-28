//
//  InvitePeopleSheet.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

/// Invite People's three cards for a viewer with `can_invite` (surface 1, frame 1a, node 12844:60),
/// in the Group Money sheet's style: each link opens its own share sheet (Decision 6).
enum InvitePeopleOptions {

    static func cards(
        onShareInviteLink: @escaping () -> Void,
        onShareJoinLink: @escaping () -> Void,
        onManageInvites: @escaping () -> Void
    ) -> [OptionCard] {
        [
            OptionCard(
                title: "Share Invite Link",
                subtitle: "Anyone with this link joins right away",
                icon: Image(systemName: "paperplane"),
                identifier: "invite-people-invite-link",
                action: onShareInviteLink
            ),
            OptionCard(
                title: "Share Join Link",
                subtitle: "People ask to join and you approve each one",
                icon: Image(systemName: "link"),
                identifier: "invite-people-join-link",
                action: onShareJoinLink
            ),
            OptionCard(
                title: "Manage Invites",
                subtitle: "See and revoke the invite links you've made",
                icon: Image(systemName: "list.bullet"),
                identifier: "invite-people-manage",
                action: onManageInvites
            ),
        ]
    }
}

/// Presents Invite People and the share sheet its card picks, once the cards have gone.
///
/// Opening the cards creates nothing (Decision 9). Share Invite Link makes the current link when
/// there is none and opens the invite share sheet at once, its pill on "Creating link…" until the
/// link returns; a failure closes that sheet and shows frame 1c or 1e.
private struct InvitePeoplePresenter: ViewModifier {

    let conversationID: ConversationID
    let canInvite: Bool
    @Binding var isPresented: Bool
    let onManageInvites: () -> Void
    let onInvited: (ConversationID) -> Void

    private enum Action {
        case shareInviteLink
        case shareJoinLink
        case manageInvites
    }

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

    @Environment(ConversationController.self) private var conversationController
    @Environment(SessionContainer.self) private var sessionContainer

    @State private var links: GroupInviteLinks?
    /// The card picked, run once the cards' sheet has gone so the next one can present.
    @State private var pendingAction: Action?
    @State private var share: Share?
    @State private var dialogItem: DialogItem?
    /// A failed create's dialog, held until the invite share sheet has gone.
    @State private var pendingDialog: DialogItem?

    private var title: String {
        conversationController.conversation(withID: conversationID)?.title ?? ""
    }

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: canInvite ? $isPresented : .constant(false), onDismiss: runPendingAction) {
                OptionCardSheet(
                    title: InviteLinkCopy.sheetTitle(groupName: title),
                    options: InvitePeopleOptions.cards(
                        onShareInviteLink: { pendingAction = .shareInviteLink },
                        onShareJoinLink: { pendingAction = .shareJoinLink },
                        onManageInvites: { pendingAction = .manageInvites }
                    )
                )
                .task { await loadLinks() }
            }
            .fullScreenCover(isPresented: canInvite ? .constant(false) : $isPresented) {
                ShareToChatsSheet(subject: .group(conversationID), isPresented: $isPresented, onInvited: onInvited)
            }
            .fullScreenCover(item: $share, onDismiss: showPendingDialog) { share in
                switch share {
                case .invite(let links):
                    ShareToChatsSheet(subject: .inviteLink(conversationID, links), isPresented: isSharing, onInvited: invited)
                case .join:
                    ShareToChatsSheet(subject: .group(conversationID), isPresented: isSharing, onInvited: invited)
                }
            }
            .dialog(item: $dialogItem)
    }

    private var isSharing: Binding<Bool> {
        Binding { share != nil } set: { if !$0 { share = nil } }
    }

    /// Reads which link is current; makes nothing.
    private func loadLinks() async {
        try? await inviteLinks().load()
    }

    private func inviteLinks() -> GroupInviteLinks {
        if let links { return links }
        let links = GroupInviteLinks(conversationID: conversationID, service: sessionContainer.inviteLinks)
        self.links = links
        return links
    }

    private func runPendingAction() {
        guard let action = pendingAction else { return }
        pendingAction = nil
        switch action {
        case .shareInviteLink: shareInviteLink()
        case .shareJoinLink: share = .join
        case .manageInvites: onManageInvites()
        }
    }

    private func shareInviteLink() {
        let links = inviteLinks()
        guard !links.isCreating else { return }
        share = .invite(links)
        Task {
            do {
                _ = try await links.currentLink()
            } catch {
                pendingDialog = InviteLinkDialogs.createFailed(
                    error,
                    onManage: onManageInvites,
                    onShareGroupLink: { share = .join }
                )
                share = nil
            }
        }
    }

    private func showPendingDialog() {
        guard let pendingDialog else { return }
        self.pendingDialog = nil
        dialogItem = pendingDialog
    }

    private func invited(_ chatID: ConversationID) {
        share = nil
        onInvited(chatID)
    }
}

extension View {

    /// Invite People for a group: the three cards for a viewer with `can_invite`, and the plain
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

#Preview("Invite People") {
    Background(color: .backgroundMain) {
        VStack {
            Spacer()
            OptionCardList(
                title: "Invite to Bike Club",
                options: InvitePeopleOptions.cards(onShareInviteLink: {}, onShareJoinLink: {}, onManageInvites: {}),
                onSelect: { _ in }
            )
            .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .padding(8)
        }
    }
}
