//
//  NotificationPresentation.swift
//  FlipcashCore
//

import Foundation
import UserNotifications

/// Whether a push that arrived while the app is in the foreground should be shown, and if not, why.
///
/// Suppression is about presentation only. The push is still delivered and still stored — the
/// server sends a muted chat's message deliberately so the client can keep the transcript and the
/// unread count complete; it just must not interrupt.
public enum NotificationPresentationDecision: Equatable, Sendable {
    case present
    /// The chat is muted for this viewer, per the flag the server set on the payload.
    case suppressedMuted
    /// The user is already reading this chat.
    case suppressedOpenConversation

    /// What to hand back from `userNotificationCenter(_:willPresent:)`.
    public var options: UNNotificationPresentationOptions {
        switch self {
        case .present:
            return [.badge, .list, .sound, .banner]
        case .suppressedMuted, .suppressedOpenConversation:
            return []
        }
    }
}

extension NotificationPayload {

    /// Decides how a foreground push should present.
    ///
    /// Mute is read from the payload rather than from local state: the flag is the server's answer
    /// at send time, it is the only thing the notification service extension can see, and reading
    /// the same source in both paths keeps them from disagreeing.
    ///
    /// `isViewingConversation` is asked only for a chat push that isn't already suppressed.
    public static func presentationDecision(
        _ userInfo: [AnyHashable: Any],
        isViewingConversation: (ConversationID) -> Bool
    ) -> NotificationPresentationDecision {
        if isMuted(userInfo) {
            return .suppressedMuted
        }
        if let conversationID = chatID(userInfo), isViewingConversation(conversationID) {
            return .suppressedOpenConversation
        }
        return .present
    }
}
