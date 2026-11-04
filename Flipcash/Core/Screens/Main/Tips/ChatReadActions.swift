//
//  ChatReadActions.swift
//  Flipcash
//

import Foundation
import Observation
import FlipcashCore

/// The read action a chat row offers: Mark as Read while the chat is unread, Mark as Unread otherwise.
enum ChatReadAction: Equatable {
    case markRead
    case markUnread

    /// The swipe and menu label.
    var title: String {
        switch self {
        case .markRead:   "Mark as Read"
        case .markUnread: "Mark as Unread"
        }
    }

    /// The SF Symbol the swipe and menu draw.
    /// The shorter title drawn under the swipe action's circle, as the select-mode capsule reads.
    var swipeTitle: String {
        switch self {
        case .markRead:   "Read"
        case .markUnread: "Unread"
        }
    }

    var systemImage: String {
        switch self {
        case .markRead:   "checkmark.message"
        case .markUnread: "message.badge"
        }
    }
}

/// Where a read action came from. The `Chat Marked Unread` and `Chat Marked Read` events carry it
/// once the shared analytics catalogue that defines them is pinned.
enum ChatReadSource: Equatable {
    case swipe
    case menu
    case selection
}

/// The Chats list's select mode: whether it is on, and which chats are picked.
///
/// Owned by the tab view, which hides the tab bar while it is on, and handed to the list through the
/// environment.
@MainActor
@Observable
final class ChatSelection {

    private(set) var isActive = false
    private(set) var selected: Set<ConversationID> = []

    /// Enters select mode with nothing selected.
    func begin() {
        selected = []
        isActive = true
    }

    /// Leaves select mode.
    func end() {
        isActive = false
        selected = []
    }

    func toggle(_ id: ConversationID) {
        if selected.contains(id) {
            selected.remove(id)
        } else {
            selected.insert(id)
        }
    }

    /// Drops picks that are no longer in the list, so an archived or left chat isn't acted on.
    func retain(_ ids: Set<ConversationID>) {
        let kept = selected.intersection(ids)
        if kept != selected { selected = kept }
    }
}

/// What the select-mode read capsule does.
enum ChatSelectionReadToggle: Equatable {
    /// Nothing selected: the capsule is Read All.
    case readAll
    /// At least one selected chat is unread: read them all.
    case read
    /// Every selected chat is read: mark them all.
    case unread

    init(selectedUnread: [Bool]) {
        if selectedUnread.isEmpty {
            self = .readAll
        } else if selectedUnread.contains(true) {
            self = .read
        } else {
            self = .unread
        }
    }

    var title: String {
        switch self {
        case .readAll: "Read All"
        case .read:    "Read"
        case .unread:  "Unread"
        }
    }
}

/// What the select-mode mute capsule does.
enum ChatSelectionMute: Equatable {
    /// At least one selected chat is audible: open the mute sheet once for all of them.
    case mute
    /// Every selected chat is muted: unmute them all.
    case unmute

    init(selectedMuted: [Bool]) {
        self = !selectedMuted.isEmpty && selectedMuted.allSatisfy { $0 } ? .unmute : .mute
    }

    var title: String {
        switch self {
        case .mute:   "Mute"
        case .unmute: "Unmute"
        }
    }
}
