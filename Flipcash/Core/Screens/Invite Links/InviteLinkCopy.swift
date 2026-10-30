//
//  InviteLinkCopy.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCore

/// The invite sheet's and Manage Invites' strings (frames 1a–1e, 2a–2e).
enum InviteLinkCopy {

    static let creating = "Creating link…"
    static let footnote = "Anyone with this link can join and see who’s in the group. Share it only with people you want in the group"
    static let cantShare = "Can’t share from this device"

    /// Under an invite link's group card QR.
    static let cardScan = "Scan to join"
    /// Under an invite link's group card (frame 1j).
    static let cardFootnote = "Anyone who scans this card joins without approval until the link expires or you revoke it."

    /// "Link expires Nov 3", or "Link never expires", under an invite link's group card QR.
    static func cardExpiry(_ expiresAt: Date?) -> String {
        expiresAt.map { "Link expires \(day($0))" } ?? "Link never expires"
    }

    static func sheetTitle(groupName: String) -> String {
        groupName.isEmpty ? "Invite People" : "Invite to \(groupName)"
    }

    /// "Created Oct 27".
    static func created(_ invite: Invite) -> String? {
        invite.createdAt.map { "Created \(day($0))" }
    }

    /// "3 joined", or "3 of 10 joined" for a link with a use limit.
    static func joined(_ invite: Invite) -> String {
        invite.maxUses == 0 ? "\(invite.useCount) joined" : "\(invite.useCount) of \(invite.maxUses) joined"
    }

    /// "Expires Nov 3", or "Never expires".
    static func expiry(_ invite: Invite) -> String {
        invite.expiresAt.map { "Expires \(day($0))" } ?? "Never expires"
    }

    /// The host sheet's caption under the invite link (frame 1m): "0 joined · Expires Nov 3".
    static func cardCaption(_ invite: Invite) -> String {
        "\(joined(invite)) · \(expiry(invite))"
    }

    /// The host sheet's caption under the plain link (frame 1m′).
    static let plainLinkCaption = "People who open this link ask to join"
    /// The host sheet's pill before the current link exists: nothing is made on open (Decision 9).
    static let noLinkYet = "No link yet"

    /// The Approve New Members row's subtitle for the switch's position.
    static func approveSubtitle(isOn: Bool) -> String {
        isOn ? "You approve each person in Join Requests" : "Anyone with the link joins right away"
    }

    /// The sheet's meta line under the current link: "Expires Nov 3 · 0 joined".
    static func sheetMeta(_ invite: Invite) -> String {
        "\(expiry(invite)) · \(joined(invite))"
    }

    /// A Manage Invites row's second line.
    static func rowDetail(_ entry: GroupInviteLinks.Entry) -> String {
        let invite = entry.invite
        switch invite.status {
        case .active:
            return entry.url == nil
                ? "\(joined(invite)) · \(cantShare)"
                : "\(joined(invite)) · \(expiry(invite))"
        case .expired:
            let ended = invite.expiresAt.map { "Expired \(day($0))" } ?? "Expired"
            return "\(ended) · \(joined(invite))"
        case .revoked:
            // The proto carries no revoke time, so the date the frame shows isn't available.
            return "Revoked · \(joined(invite))"
        case .exhausted:
            return "Reached its limit · \(joined(invite))"
        case .unknown:
            return joined(invite)
        }
    }

    private static func day(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }
}
