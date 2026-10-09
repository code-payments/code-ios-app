//
//  ShareChatSelection.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// Which chats the share extension offers, and which one a share was aimed at.
public enum ShareChatSelection {

    /// The chats a share can go into, most recent first. Hidden chats are the ones the user removed
    /// from the list, so they stay out of the picker too.
    public static func candidates(from conversations: [Conversation]) -> [Conversation] {
        conversations
            .filter { !$0.isHidden }
            .sorted { $0.lastActivity > $1.lastActivity }
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
