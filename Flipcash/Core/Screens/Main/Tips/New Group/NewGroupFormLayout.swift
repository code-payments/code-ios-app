//
//  NewGroupFormLayout.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// What the New Group form shows for a privacy and shell.
struct NewGroupFormLayout: Equatable {

    /// How Create is drawn in the bar.
    enum CreatePill: Equatable {
        /// Today's bar button, whose prominence follows its enabled state.
        case prominent
        case grey
        case blue
    }

    let privacy: GroupPrivacy
    let showsGroupMoney: Bool

    var title: String {
        privacy == .private ? "New Group" : "New Community Chat"
    }

    var namePlaceholder: String {
        "Group Name (Required)"
    }

    var showsPrivacyFootnote: Bool {
        privacy == .private
    }

    var showsCommunitySections: Bool {
        privacy == .public
    }

    func createPill(isEnabled: Bool) -> CreatePill {
        .prominent
    }
}
