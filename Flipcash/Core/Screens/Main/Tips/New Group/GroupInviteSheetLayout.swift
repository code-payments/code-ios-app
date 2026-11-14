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
    /// Whether opening the link joins the group outright. A current invite link does; the plain
    /// `/chat/{uuid}` link, shared while Approve New Members is on or by a member who can't invite,
    /// asks the host first.
    let admitsAnyone: Bool

    init(showsGroupMoney: Bool, admitsAnyone: Bool = true) {
        self.showsGroupMoney = showsGroupMoney
        self.admitsAnyone = admitsAnyone
    }

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

    /// The line under the link. The shell's caption promises open entry, so a link that asks the
    /// host first goes without one rather than repeat ``message``.
    var linkCaption: String? {
        guard showsGroupMoney else { return InviteLinkCopy.groupSheetLine }
        return admitsAnyone ? "Anyone with the link can join." : nil
    }

    var tileTitles: [String] {
        showsGroupMoney ? ["Copy Link", "Share Link", "QR Code"] : ShareToChatsSheet.groupTileTitles
    }

    var tilesAreSquare: Bool {
        showsGroupMoney
    }

    /// Whether the sheet opens at full height. Neither shell's does: the Group Money shell's sheet
    /// fits its content as today's does, where frame 1-07 draws a full screen.
    var opensFullHeight: Bool {
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

    /// The group-ready card's button. The shell opens the Invite People sheet for everyone;
    /// without it, a private group's host goes straight to the share sheet.
    static func forGroupReady(showsGroupMoney: Bool, canInvite: Bool, isPrivate: Bool) -> Self {
        if showsGroupMoney { return .invitePeopleSheet }
        if isPrivate && canInvite { return .shareSheet }
        return forGroupInfo(showsGroupMoney: showsGroupMoney, canInvite: canInvite)
    }

    /// Group info's Invite People, which `invitePeople(_:canInvite:…)` presents: the host's link
    /// card, or the plain link's share sheet for a member who can't invite. The Group Money shell
    /// keeps today's sheets here.
    static func forGroupInfo(showsGroupMoney: Bool, canInvite: Bool) -> Self {
        canInvite ? .linkCard : .shareSheet
    }
}
