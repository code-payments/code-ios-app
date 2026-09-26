//
//  ChatNotificationCategory.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// Identifiers for the chat-message notification categories. Shared by the app
/// (registers the categories), `NotificationService` (tags the push), and the
/// content extension (declares + handles them).
///
/// There are two because the actions differ: a DM offers Reply and Send Cash, a group offers Reply
/// alone. A group is paid by a cash link posted from inside the chat, never from a push action.
public enum ChatNotificationCategory {
    public static let id = "CHAT_MESSAGE"
    public static let groupID = "CHAT_MESSAGE_GROUP"
    public static let replyActionID = "CHAT_REPLY"
    public static let sendCashActionID = "CHAT_SEND_CASH"

    /// The category a chat push carries, by the chat it came from.
    public static func id(for type: ConversationType) -> String {
        switch type {
        case .group:               groupID
        case .contactDm, .tipDm:   id
        }
    }
}
