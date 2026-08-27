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
    case profilePicture(isCompleted: Bool)
    case minimumTipAmount(isCompleted: Bool)

    var id: String { title }

    var isCompleted: Bool {
        switch self {
        case .profilePicture(let done), .minimumTipAmount(let done): return done
        }
    }

    var title: String {
        switch self {
        case .profilePicture:   return "Add a profile picture"
        case .minimumTipAmount: return "Set your minimum tip amount"
        }
    }

    var subtitle: String {
        switch self {
        case .profilePicture:   return "Select a photo from your gallery"
        case .minimumTipAmount: return "Decide what size tip matters to you"
        }
    }

    @MainActor var icon: Image {
        switch self {
        case .profilePicture:   return .asset(.peopleCircle)
        case .minimumTipAmount: return .asset(.coins)
        }
    }
}

/// Whether the You tab draws the profile checklist, and with which chores
/// checked off.
///
/// Both chores are read straight off the profile rather than from a local
/// dismissal flag, so a picture or fee that disappears across a profile refresh
/// puts the card back on its own.
struct ProfileTutorialState: Equatable {

    /// Withholds the card until a profile has loaded, so a session that has not
    /// fetched one yet does not flash an all-incomplete checklist.
    let hasProfile: Bool
    let hasProfilePicture: Bool
    let hasMinimumTipAmount: Bool

    init(hasProfile: Bool, hasProfilePicture: Bool, hasMinimumTipAmount: Bool) {
        self.hasProfile = hasProfile
        self.hasProfilePicture = hasProfilePicture
        self.hasMinimumTipAmount = hasMinimumTipAmount
    }

    init(profile: Profile?) {
        self.init(
            hasProfile: profile != nil,
            hasProfilePicture: profile?.profilePicture != nil,
            hasMinimumTipAmount: profile?.minDmChatInitFee != nil
        )
    }

    var items: [ProfileTutorialItem] {
        [
            .profilePicture(isCompleted: hasProfilePicture),
            .minimumTipAmount(isCompleted: hasMinimumTipAmount),
        ]
    }

    var isComplete: Bool { hasProfilePicture && hasMinimumTipAmount }

    var isVisible: Bool { hasProfile && !isComplete }
}
