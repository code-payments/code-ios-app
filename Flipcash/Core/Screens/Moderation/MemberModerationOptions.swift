//
//  MemberModerationOptions.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCore

/// What the viewer may do to one member from a Members row swipe or the member sheet.
nonisolated struct MemberModerationOptions: Equatable {

    /// The silence entry a row or sheet offers: Restrict for a member who can talk, Lift for one who can't.
    enum SilenceAction: Equatable {
        case restrict
        case lift
    }

    /// Restrict or Lift, or nil when the viewer can't silence this member.
    let silence: SilenceAction?
    /// Whether the viewer can remove this member.
    let canRemove: Bool
    /// Whether the member's restriction is shown, which only the group's moderators see.
    let showsRestriction: Bool

    /// Whether there is a group action at all: the swipe and the sheet's "In <group>" section exist only then.
    var hasGroupActions: Bool {
        silence != nil || canRemove
    }

    /// Whether the sheet offers Report, which it does whenever it has no group section.
    var showsReport: Bool {
        !hasGroupActions
    }

    /// Resolves the options under `group-moderation.md`'s rules: nothing on the creator or on the
    /// viewer's own entry, and each action behind its own permission.
    static func resolve(canSilence: Bool, canBan: Bool, isCreator: Bool, isSelf: Bool, isRestricted: Bool) -> MemberModerationOptions {
        let isModerator = canSilence || canBan
        guard !isCreator, !isSelf else {
            return MemberModerationOptions(silence: nil, canRemove: false, showsRestriction: false)
        }
        return MemberModerationOptions(
            silence: canSilence ? (isRestricted ? .lift : .restrict) : nil,
            canRemove: canBan,
            showsRestriction: isModerator && isRestricted
        )
    }
}

extension GroupModerationCopy {

    /// A restricted member's status line on their Members row and in the member sheet:
    /// "Restricted · 6h 12m left", or "Restricted" for Forever.
    static func restrictedStatus(_ silence: ConversationSilenceState, now: Date) -> String {
        switch silence {
        case .forever:
            return "Restricted"
        case .until(let end):
            return "Restricted · \(timeLeft(until: end, now: now))"
        }
    }

    /// The time to `end` in its two largest units, rounded down to the minute and never under a
    /// minute: "6d 23h left", "6h 12m left", "6h left", "59m left".
    static func timeLeft(until end: Date, now: Date) -> String {
        let minutes = max(1, Int(end.timeIntervalSince(now) / 60))
        let days = minutes / (24 * 60)
        let hours = (minutes % (24 * 60)) / 60
        let mins = minutes % 60
        if days > 0 {
            return hours > 0 ? "\(days)d \(hours)h left" : "\(days)d left"
        }
        if hours > 0 {
            return mins > 0 ? "\(hours)h \(mins)m left" : "\(hours)h left"
        }
        return "\(mins)m left"
    }
}
