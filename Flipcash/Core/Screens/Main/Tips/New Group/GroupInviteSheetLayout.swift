//
//  GroupInviteSheetLayout.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI

/// What the group share sheet shows for a shell. The Group Money shell's Invite People sheet
/// (node 13729:672) closes from the left, names the group, says what the link is for and draws three
/// square tiles; with the shell off, the sheet is today's.
struct GroupInviteSheetLayout: Equatable {

    let showsGroupMoney: Bool

    var title: String {
        "Invite People"
    }

    var closeEdge: HorizontalEdge {
        showsGroupMoney ? .leading : .trailing
    }

    /// The group's avatar and name under the title bar.
    var showsGroupIdentity: Bool {
        showsGroupMoney
    }

    /// The line over the link.
    var message: String? {
        showsGroupMoney ? "Send this link to the people you want in your group." : nil
    }

    /// The line under the link.
    var linkCaption: String {
        showsGroupMoney ? "Anyone with the link can join." : InviteLinkCopy.groupSheetLine
    }

    var tileTitles: [String] {
        showsGroupMoney ? ["Copy Link", "Share Link", "QR Code"] : ShareToChatsSheet.groupTileTitles
    }

    var tilesAreSquare: Bool {
        showsGroupMoney
    }

    /// The shell's sheet is a full screen (node 13729:672); today's fits its content.
    var opensFullHeight: Bool {
        showsGroupMoney
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

    /// The group-ready card's button. The shell has one Invite People sheet for everyone; without
    /// it, a private group's host goes straight to the share sheet.
    static func forGroupReady(showsGroupMoney: Bool, canInvite: Bool, isPrivate: Bool) -> Self {
        if showsGroupMoney { return .invitePeopleSheet }
        if isPrivate && canInvite { return .shareSheet }
        return forGroupInfo(showsGroupMoney: showsGroupMoney, canInvite: canInvite)
    }

    /// Group info's Invite People.
    static func forGroupInfo(showsGroupMoney: Bool, canInvite: Bool) -> Self {
        if showsGroupMoney { return .invitePeopleSheet }
        return canInvite ? .linkCard : .shareSheet
    }
}
