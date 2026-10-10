//
//  ShareChatSelection.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// Which chats the share extension offers, and which one a share was aimed at.
public enum ShareChatSelection {

    /// The chats a share can go into: exactly the Chats tab's main list, so the picker matches what
    /// the user sees in the app. Hidden and archived chats, contact DMs and unjoined groups stay out.
    public static func candidates(
        from conversations: [Conversation],
        joinedGroupIDs: Set<ConversationID>,
        archivedIDs: Set<ConversationID>
    ) -> [Conversation] {
        ChatListSelection.mainList(from: conversations, joinedGroupIDs: joinedGroupIDs, archivedIDs: archivedIDs)
    }

    /// The chat named by an `INSendMessageIntent.conversationIdentifier`, when it is one of
    /// `conversations`. The identifier is a chat's link form: the dashed UUID of a group or the
    /// base64url of a DM, which is what `ConversationID.linkPathComponent` produces. Anything else, or
    /// a chat the picker does not offer, selects nothing.
    public static func preselected(conversationIdentifier: String?, in conversations: [Conversation]) -> ConversationID? {
        guard let conversationIdentifier,
              let id = ConversationID(uuidString: conversationIdentifier) ?? ConversationID(base64URLEncoded: conversationIdentifier)
        else { return nil }
        return conversations.contains { $0.id == id } ? id : nil
    }
}
