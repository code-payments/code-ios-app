//
//  InviteLinkDialogs.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

/// The invite links' bottom bars (frames 1c, 1e, 2c).
@MainActor
enum InviteLinkDialogs {

    /// What a failed `CreateInvite` shows: 1c for too many links, 1e for DENIED, and a generic
    /// failure for anything else, `INVALID_SIGNATURE` included.
    static func createFailed(_ error: Error, onManage: @escaping () -> Void, onShareGroupLink: @escaping () -> Void) -> DialogItem {
        switch error as? ErrorCreateInvite {
        case .tooManyInvites:
            // The server allows 20 active links per group (Decision 7).
            .info(
                title: "Too Many Active Links",
                subtitle: "You have 20 active invite links. Revoke one in Manage Invites to make another"
            ) {
                DialogAction.standard("Manage Invites", action: onManage)
                DialogAction.cancel()
            }
        case .denied:
            // Only staff may make invites for now (Decision 10). Offers the plain link, no retry.
            .info(
                title: "Invite Links Aren’t Available Yet",
                subtitle: "You can still share the group link. People who open it can ask to join, and you approve them"
            ) {
                DialogAction.standard("Share Group Link", action: onShareGroupLink)
                DialogAction.cancel()
            }
        default:
            .error(title: "Couldn’t Create Link", subtitle: "Something went wrong.")
        }
    }

    /// Frame 2c. Revoking removes no one.
    static func revoke(onRevoke: @escaping () -> Void) -> DialogItem {
        .alert(
            title: "Revoke this link?",
            subtitle: "No one new can join with it. People who already joined stay in the group"
        ) {
            DialogAction.destructive("Revoke Link", action: onRevoke)
            DialogAction.cancel()
        }
    }
}
