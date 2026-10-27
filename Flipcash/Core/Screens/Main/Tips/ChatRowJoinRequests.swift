//
//  ChatRowJoinRequests.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// What a hosted group's Chats row shows for the join requests waiting on it (node 12824:117): the
/// request line, which leads the subtitle, and its share of the unread pill.
struct ChatRowJoinRequests: Equatable {

    /// The people waiting, newest first.
    let requesterNames: [String]

    init(requesterNames: [String]) {
        self.requesterNames = requesterNames
    }

    init(_ members: [LobbyMember]) {
        self.init(requesterNames: members.map { $0.profile?.displayName ?? $0.profile?.username?.value ?? "" })
    }

    var count: Int { requesterNames.count }

    /// "Jasper wants to join" for one requester, "3 people want to join" for more; nil for none.
    var line: String? {
        switch count {
        case 0:
            return nil
        case 1:
            let name = requesterNames[0]
            return name.isEmpty ? "1 person wants to join" : "\(name) wants to join"
        default:
            return "\(count) people want to join"
        }
    }

    /// The row's subtitle: the request line alone, or followed by the last-message preview when the
    /// chat also has unread messages. Returns `preview` untouched when no one is waiting.
    func subtitle(preview: AttributedString?, hasUnreadMessages: Bool) -> AttributedString? {
        guard let line else { return preview }
        var subtitle = AttributedString(line)
        subtitle.foregroundColor = .unreadIndicator
        guard hasUnreadMessages, let preview, !preview.characters.isEmpty else { return subtitle }
        var rest = AttributedString(" · ")
        rest.append(preview)
        rest.foregroundColor = .textSecondary
        subtitle.append(rest)
        return subtitle
    }

    /// The unread pill's count: the requests plus the unread messages. Nil while the message count
    /// can't be known, so the row draws the bare dot rather than a number that's too low.
    func pillCount(hasUnreadMessages: Bool, unreadMessageCount: Int?) -> Int? {
        let messages = hasUnreadMessages ? unreadMessageCount : 0
        return messages.map { $0 + count }
    }
}
