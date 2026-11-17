//
//  NewGroupFormLayout.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// What the New Group form shows for a privacy and shell.
///
/// The Group Money shell's New Group (nodes 13729:462, 13729:552) is the private form with less on
/// it: one card holding the picture and the name, no footnote, and a Create pill that is grey until
/// the group has a name and blue after. The community form keeps its sections either way, since the
/// shell's + never opens it.
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

    private var isShellForm: Bool {
        showsGroupMoney && privacy == .private
    }

    var title: String {
        privacy == .private ? "New Group" : "New Community Chat"
    }

    var namePlaceholder: String {
        isShellForm ? "Group Name" : "Group Name (Required)"
    }

    var showsPrivacyFootnote: Bool {
        privacy == .private && !isShellForm
    }

    var showsCommunitySections: Bool {
        privacy == .public
    }

    func createPill(isEnabled: Bool) -> CreatePill {
        guard isShellForm else { return .prominent }
        return isEnabled ? .blue : .grey
    }
}
