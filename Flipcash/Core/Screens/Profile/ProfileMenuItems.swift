//
//  ProfileMenuItems.swift
//  Flipcash
//

import FlipcashCore

/// An entry in another user's overflow menu.
nonisolated enum ProfileMenuItem: Equatable {
    case mute
    case report
    case block
    case unblock
    /// Host-only, in the group the profile was opened from.
    case silence
    case removeFromGroup

    /// The entry's label.
    var title: String {
        switch self {
        case .mute:    return "Mute Notifications"
        case .report:  return "Report"
        case .block:   return "Block"
        case .unblock: return "Unblock"
        case .silence: return "Restrict"
        case .removeFromGroup: return "Remove from Group"
        }
    }

    /// The SF Symbol drawn beside the label.
    var systemImage: String {
        switch self {
        case .mute:    return "bell.slash"
        case .report:  return "exclamationmark.bubble"
        case .block:   return "nosign"
        case .unblock: return "checkmark.circle"
        case .silence: return "speaker.slash"
        case .removeFromGroup: return "person.badge.minus"
        }
    }

    /// Whether the entry is drawn as a destructive action. Unblock restores something, so it isn't.
    var isDestructive: Bool {
        switch self {
        case .report, .block, .removeFromGroup: return true
        case .mute, .unblock, .silence:      return false
        }
    }
}

/// The entries of another user's overflow menu.
nonisolated enum ProfileMenuItems {

    /// Mute needs a DM to silence and is hidden while blocked, since the DM is hidden too.
    static func resolve(isBlocked: Bool, hasDM: Bool) -> [ProfileMenuItem] {
        if isBlocked { return [.report, .unblock] }
        var items: [ProfileMenuItem] = []
        if hasDM { items.append(.mute) }
        items.append(contentsOf: [.report, .block])
        return items
    }

    /// The host's section for a profile opened from a group: Silence when the viewer can silence,
    /// Remove when they can ban. Empty for the group's creator, who can't be restricted, and for
    /// the viewer's own profile. Block stays in the main section and stays global.
    static func moderation(canSilence: Bool, canBan: Bool, isCreator: Bool, isSelf: Bool) -> [ProfileMenuItem] {
        guard !isCreator, !isSelf else { return [] }
        var items: [ProfileMenuItem] = []
        if canSilence { items.append(.silence) }
        if canBan { items.append(.removeFromGroup) }
        return items
    }
}

extension ProfileMenuItem {
    /// The shared catalogue's action for this entry, or nil for the group-moderation entries it doesn't cover.
    var analyticsAction: SharedCoreKit.ProfileMenuAction? {
        switch self {
        case .mute:            .mute
        case .report:          .report
        case .block:           .block
        case .unblock:         .unblock
        case .silence:         nil
        case .removeFromGroup: nil
        }
    }
}
