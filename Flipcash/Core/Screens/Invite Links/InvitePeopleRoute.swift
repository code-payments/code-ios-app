//
//  InvitePeopleRoute.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// What a group's Invite People button opens.
enum InvitePeopleRoute: Equatable {
    /// The Invite People sheet, presented through the router: the share sheet Manage Invites'
    /// Share Link opens.
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
