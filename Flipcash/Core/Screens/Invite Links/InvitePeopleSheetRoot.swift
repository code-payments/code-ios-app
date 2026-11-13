//
//  InvitePeopleSheetRoot.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// A group's Invite People sheet as the router presents it in the Group Money shell (node
/// 13729:672): the group's link and the ways to send it, with no chat picker, Approve New Members
/// switch or Manage Invites row.
///
/// It shares the link the group-ready card's share sheet does today: a host's current invite link,
/// made first when the group has none, or the plain link while Approve New Members is on, for a
/// member who can't invite, or once making a link has failed and the viewer picked the plain one.
struct InvitePeopleSheetRoot: View {

    let conversationID: ConversationID

    @Environment(AppRouter.self) private var router
    @Environment(SessionContainer.self) private var sessionContainer
    @Environment(ConversationController.self) private var conversationController

    @State private var sharesPlainLink = false
    @State private var opensManageInvites = false
    @State private var dialog: DialogItem?

    var body: some View {
        sheet
            .dialog(item: $dialog)
            .task(id: target) {
                guard target == .currentLink else { return }
                do {
                    _ = try await links.currentLink()
                } catch {
                    // The dialog is a sheet on this one, so this sheet stays up under it and closes
                    // when it does.
                    dialog = InviteLinkDialogs.cardCreateFailed(
                        error,
                        onManage: {
                            opensManageInvites = true
                            router.dismissSheet()
                            router.push(.inviteLinks(conversationID))
                        },
                        onShare: { _ in sharesPlainLink = true }
                    )
                    .onDismiss {
                        if GroupReadyInvite.closesSheetAfterFailedLink(sharesPlainLink: sharesPlainLink, opensManageInvites: opensManageInvites) {
                            router.dismissSheet()
                        }
                    }
                }
            }
    }

    @ViewBuilder
    private var sheet: some View {
        switch target {
        case .currentLink:
            ShareToChatsSheet(subject: .inviteLink(conversationID, links), isPresented: isPresented, isInvitePeople: true, onInvited: invited)
        case .plainLink:
            ShareToChatsSheet(subject: .group(conversationID), isPresented: isPresented, isInvitePeople: true, onInvited: invited)
        }
    }

    private var target: GroupReadyInvite.Target {
        let canInvite = conversationController.conversation(withID: conversationID)?.canInvite ?? false
        guard canInvite, !sharesPlainLink else { return .plainLink }
        return GroupReadyInvite.target(isApproving: sessionContainer.approveNewMembers.isOn(for: conversationID))
    }

    private var links: GroupInviteLinks {
        sessionContainer.groupInviteLinks.links(for: conversationID)
    }

    private var isPresented: Binding<Bool> {
        Binding { true } set: { if !$0 { router.dismissSheet() } }
    }

    private func invited(_ chatID: ConversationID) {
        router.dismissSheet()
        router.openSharedChat(chatID)
    }
}
