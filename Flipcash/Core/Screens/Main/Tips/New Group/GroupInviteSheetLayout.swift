//
//  GroupInviteSheetLayout.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI

/// What the group share sheet shows for a shell.
struct GroupInviteSheetLayout: Equatable {

    let showsGroupMoney: Bool

    var title: String {
        "Invite People"
    }

    var closeEdge: HorizontalEdge {
        .trailing
    }

    var showsGroupIdentity: Bool {
        false
    }

    var message: String? {
        nil
    }

    var linkCaption: String {
        InviteLinkCopy.groupSheetLine
    }

    var tileTitles: [String] {
        ShareToChatsSheet.groupTileTitles
    }

    var tilesAreSquare: Bool {
        false
    }
}

/// What a group's Invite People button opens.
enum InvitePeopleRoute: Equatable {
    /// The Invite People sheet, presented through the router.
    case invitePeopleSheet
    /// The share sheet for the group's link.
    case shareSheet
    /// The host's link card, with Approve New Members and Manage Invites.
    case linkCard

    /// The group-ready card's button.
    static func forGroupReady(showsGroupMoney: Bool, canInvite: Bool, isPrivate: Bool) -> Self {
        if isPrivate && canInvite { return .shareSheet }
        return forGroupInfo(showsGroupMoney: showsGroupMoney, canInvite: canInvite)
    }

    /// Group info's Invite People.
    static func forGroupInfo(showsGroupMoney: Bool, canInvite: Bool) -> Self {
        canInvite ? .linkCard : .shareSheet
    }
}
