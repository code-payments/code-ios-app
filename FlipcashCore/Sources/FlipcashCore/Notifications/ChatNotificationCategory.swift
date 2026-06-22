import Foundation

/// Identifiers for the chat-message notification category. Shared by the app
/// (registers the category), `NotificationService` (tags the push), and the
/// content extension (declares + handles the category).
public enum ChatNotificationCategory {
    public static let id = "CHAT_MESSAGE"
    public static let replyActionID = "CHAT_REPLY"
    public static let sendCashActionID = "CHAT_SEND_CASH"
}
