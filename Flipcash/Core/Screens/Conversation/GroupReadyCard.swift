//
//  GroupReadyCard.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import FlipcashCore

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

    /// The chat-list line for a conversation that has no message at all: an invitation while the
    /// group-ready card would show, "Nothing yet" otherwise. Client-only, so it follows the card
    /// leaving once someone joins.
    static func emptyPreview(for conversation: Conversation) -> String {
        isShown(conversation)
            ? String(localized: "Invite people to get started", comment: "Chat list preview of a group the viewer is alone in and has not messaged")
            : String(localized: "Nothing yet", comment: "Chat list preview of a chat with no messages")
    }
}

extension View {

    /// The Invite People sheet group info opens, for the group-ready card's button.
    @ViewBuilder
    func groupReadyInvite(
        conversationID: ConversationID?,
        canInvite: Bool,
        isPresented: Binding<Bool>,
        router: AppRouter
    ) -> some View {
        if let conversationID {
            invitePeople(
                conversationID,
                canInvite: canInvite,
                isPresented: isPresented,
                onManageInvites: { router.push(.inviteLinks(conversationID)) }
            ) { chatID in
                router.openSharedChat(chatID)
            }
        } else {
            self
        }
    }
}
