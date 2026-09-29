//
//  ProfileTutorial.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// A chore in the You tab's "Finish Your Profile" checklist (Figma node
/// 9544:18140).
nonisolated enum ProfileTutorialItem: TutorialItemPresentable {
    case displayName(isCompleted: Bool)
    case profilePicture(isCompleted: Bool)
    case minimumTipAmount(isCompleted: Bool)

    var id: String { title }

    var isCompleted: Bool {
        switch self {
        case .displayName(let done), .profilePicture(let done), .minimumTipAmount(let done): return done
        }
    }

    var title: String {
        switch self {
        case .displayName:      return "Add your display name"
        case .profilePicture:   return "Add a profile picture"
        case .minimumTipAmount: return "Set your minimum to chat"
        }
    }

    var subtitle: String {
        switch self {
        case .displayName:      return "Choose the name people see in chat"
        case .profilePicture:   return "Select a photo from your gallery"
        case .minimumTipAmount: return "Decide what someone must send to start chatting"
        }
    }

    @MainActor var icon: Image {
        switch self {
        case .displayName:      return .asset(.pencil)
        case .profilePicture:   return .asset(.peopleCircle)
        case .minimumTipAmount: return .asset(.coins)
        }
    }
}

/// Whether the You tab draws the profile checklist, and with which chores
/// checked off.
///
/// Every chore is read straight off the profile rather than from a local
/// dismissal flag, so a name, picture or fee that disappears across a profile
/// refresh puts the card back on its own.
struct ProfileTutorialState: Equatable {

    /// Withholds the card until a profile has loaded, so a session that has not
    /// fetched one yet does not flash an all-incomplete checklist.
    let hasProfile: Bool
    let hasDisplayName: Bool
    let hasProfilePicture: Bool
    let hasMinimumTipAmount: Bool

    init(hasProfile: Bool, hasDisplayName: Bool, hasProfilePicture: Bool, hasMinimumTipAmount: Bool) {
        self.hasProfile = hasProfile
        self.hasDisplayName = hasDisplayName
        self.hasProfilePicture = hasProfilePicture
        self.hasMinimumTipAmount = hasMinimumTipAmount
    }

    init(profile: Profile?) {
        self.init(
            hasProfile: profile != nil,
            hasDisplayName: profile?.displayName?.isEmpty == false,
            hasProfilePicture: profile?.profilePicture != nil,
            hasMinimumTipAmount: profile?.minDmChatInitFee != nil
        )
    }

    var items: [ProfileTutorialItem] {
        [
            .displayName(isCompleted: hasDisplayName),
            .profilePicture(isCompleted: hasProfilePicture),
            .minimumTipAmount(isCompleted: hasMinimumTipAmount),
        ]
    }

    var isComplete: Bool { hasDisplayName && hasProfilePicture && hasMinimumTipAmount }

    var isVisible: Bool { hasProfile && !isComplete }
}
