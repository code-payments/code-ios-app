//
//  ProfilePinnedAction.swift
//  Flipcash
//

import FlipcashCore

/// The one button pinned under another user's profile, decided from who the viewer is looking at.
nonisolated enum ProfilePinnedAction: Equatable {
    case none
    case unblock
    case openChat(ConversationID)
    /// Pays `FiatAmount` to open the chat.
    case startChatting(FiatAmount)
    /// The fee isn't known yet, so the tap opens the amount screen instead of the confirmation sheet.
    case startChattingUnpriced

    /// Blocked beats everything but the viewer's own profile: a blocked person's DM is hidden, and
    /// opening or starting a chat with them would undo the block.
    static func resolve(isSelf: Bool, isBlocked: Bool, dmID: ConversationID?, fee: FiatAmount?) -> ProfilePinnedAction {
        if isSelf { return .none }
        if isBlocked { return .unblock }
        if let dmID { return .openChat(dmID) }
        if let fee { return .startChatting(fee) }
        return .startChattingUnpriced
    }

    /// The button's label, or nil when nothing is pinned.
    var title: String? {
        switch self {
        case .none:                  return nil
        case .unblock:               return "Unblock"
        case .openChat:              return "Open Chat"
        case .startChatting(let fee): return "Send \(fee.formatted()) to Start Chatting"
        case .startChattingUnpriced: return "Start Chatting"
        }
    }
}
