//
//  GroupReadyCard.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// When the "Your Group Is Ready" card shows at the head of a group's transcript.
enum GroupReadyCard {

    /// The card shows while the viewer is alone in a group they may invite people to.
    ///
    /// - Parameter memberCount: the roster summary's count, or nil when the roster has not landed.
    ///   A store that has not heard from the server holds a count of zero, which is unresolved too:
    ///   a group the viewer is looking at has at least them in it.
    static func isShown(isGroup: Bool, memberCount: UInt64?, viewerCanInvite: Bool) -> Bool {
        guard isGroup, let memberCount, memberCount > 0 else { return false }
        return memberCount == 1 && viewerCanInvite
    }

    /// How the card is drawn.
    static func style(showsGroupMoney: Bool) -> ChatInviteCardStyle {
        showsGroupMoney ? .emptyState : .incomingBubble
    }

    static func isShown(_ conversation: Conversation?) -> Bool {
        guard let conversation else { return false }
        return isShown(
            isGroup: conversation.type == .group,
            memberCount: conversation.rosterSummary.memberCount,
            // A public group's link is shareable by any member, and group info's Share opens for them
            // without can-invite, so only a private group gates the card on it.
            viewerCanInvite: conversation.canInvite || !conversation.isPrivate
        )
    }

    /// Whether the transcript draws the gate's placeholder shapes behind an empty chat.
    ///
    /// A gated chat the viewer is refused always gets them. Otherwise they only bridge an empty
    /// transcript's first load, and not while the group-ready card shows: that chat is new and has
    /// nothing to wait for, so the shapes would sit behind the card.
    static func showsGatePlaceholder(
        withholdsTranscript: Bool,
        didInitialRead: Bool,
        transcriptIsEmpty: Bool,
        cardShown: Bool
    ) -> Bool {
        (withholdsTranscript || (!didInitialRead && !cardShown)) && transcriptIsEmpty
    }

    /// The chat-list line for a conversation that has no message at all: an invitation while the
    /// group-ready card would show, "Nothing yet" otherwise. Client-only, so it follows the card
    /// leaving once someone joins.
    static func emptyPreview(for conversation: Conversation) -> String {
        isShown(conversation)
            ? String(localized: "Invite people to get started", comment: "Chat list preview of a group the viewer is alone in and has not messaged")
            : String(localized: "Nothing yet", comment: "Chat list preview of a chat with no messages")
    }
}

/// Which link the card's Invite People shares for a private group.
enum GroupReadyInvite {

    enum Target: Equatable {
        /// The current invite link, made first when the group has none.
        case currentLink
        /// The plain `/chat/{uuid}` link, because Approve New Members is on.
        case plainLink
    }

    static func target(isApproving: Bool) -> Target {
        isApproving ? .plainLink : .currentLink
    }

    /// Whether the router's Invite People sheet closes once the failed-link dialog does. With no
    /// link made, the sheet has nothing to share and its tiles stay off, so it closes as today's
    /// card presenter does, unless the viewer took the plain link (the sheet swaps to it) or went to
    /// Manage Invites (which closed it already).
    static func closesSheetAfterFailedLink(sharesPlainLink: Bool, opensManageInvites: Bool) -> Bool {
        !sharesPlainLink && !opensManageInvites
    }
}

/// Opens the share sheet straight from the card for a private group's host, with no Invite People
/// sheet in between. The sheet shows its "Creating link…" pill while the link is made or awaited.
private struct GroupReadyInvitePresenter: ViewModifier {

    private enum Share: Identifiable {
        case invite(GroupInviteLinks)
        case plain
        var id: String {
            switch self {
            case .invite: "invite"
            case .plain: "plain"
            }
        }
    }

    let conversationID: ConversationID
    @Binding var isPresented: Bool
    let router: AppRouter

    @Environment(SessionContainer.self) private var sessionContainer

    @State private var share: Share?
    @State private var dialog: DialogItem?

    func body(content: Content) -> some View {
        content
            .onChange(of: isPresented) { _, presented in
                guard presented else { return }
                isPresented = false
                open()
            }
            .dialog(item: $dialog)
            .sheet(item: $share) { share in
                switch share {
                case .invite(let links):
                    ShareToChatsSheet(subject: .inviteLink(conversationID, links), isPresented: isSharing, onInvited: invited)
                case .plain:
                    ShareToChatsSheet(subject: .group(conversationID), isPresented: isSharing, onInvited: invited)
                }
            }
    }

    private var isSharing: Binding<Bool> {
        Binding { share != nil } set: { if !$0 { share = nil } }
    }

    private func open() {
        switch GroupReadyInvite.target(isApproving: sessionContainer.approveNewMembers.isOn(for: conversationID)) {
        case .plainLink:
            share = .plain
        case .currentLink:
            let links = sessionContainer.groupInviteLinks.links(for: conversationID)
            share = .invite(links)
            Task {
                do {
                    _ = try await links.currentLink()
                } catch {
                    share = nil
                    dialog = InviteLinkDialogs.cardCreateFailed(
                        error,
                        onManage: { router.push(.inviteLinks(conversationID)) },
                        onShare: { _ in share = .plain }
                    )
                }
            }
        }
    }

    private func invited(_ chatID: ConversationID) {
        share = nil
        router.openSharedChat(chatID)
    }
}

extension View {

    /// What the group-ready card's button opens: a private group's host gets the share sheet for
    /// the current link directly; any other group keeps the Invite People sheet group info opens.
    @ViewBuilder
    func groupReadyInvite(
        conversationID: ConversationID?,
        canInvite: Bool,
        isPrivate: Bool,
        isPresented: Binding<Bool>,
        router: AppRouter
    ) -> some View {
        if let conversationID {
            if isPrivate && canInvite {
                modifier(GroupReadyInvitePresenter(conversationID: conversationID, isPresented: isPresented, router: router))
            } else {
                invitePeople(
                    conversationID,
                    canInvite: canInvite,
                    isPresented: isPresented,
                    onManageInvites: { router.push(.inviteLinks(conversationID)) }
                ) { chatID in
                    router.openSharedChat(chatID)
                }
            }
        } else {
            self
        }
    }
}
