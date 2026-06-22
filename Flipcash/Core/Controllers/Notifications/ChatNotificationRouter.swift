import FlipcashCore

nonisolated enum ChatNotificationRouter {
    /// The contact a Send Cash from the notification should pay: the synced
    /// contact when present, else a target built from the counterpart's shared
    /// phone number (mirrors `ConversationScreen.sendTarget`, #382).
    static func sendTarget(forChatID id: ConversationID, conversation: Conversation?, selfUserID: UserID) -> ResolvedContact? {
        guard let counterpart = conversation?.counterpart(excluding: selfUserID),
              counterpart.phoneE164?.isEmpty == false else { return nil }
        return ResolvedContact(counterpart: counterpart, dmChatID: id.data)
    }
}
