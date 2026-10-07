//
//  ProfileMenuItems.swift
//  Flipcash
//

/// An entry in another user's overflow menu.
nonisolated enum ProfileMenuItem: Equatable {
    case mute
    case report
    case block
    case unblock

    /// The entry's label.
    var title: String {
        switch self {
        case .mute:    return "Mute Notifications"
        case .report:  return "Report"
        case .block:   return "Block"
        case .unblock: return "Unblock"
        }
    }

    /// The SF Symbol drawn beside the label.
    var systemImage: String {
        switch self {
        case .mute:    return "bell.slash"
        case .report:  return "exclamationmark.bubble"
        case .block:   return "nosign"
        case .unblock: return "checkmark.circle"
        }
    }

    /// Whether the entry is drawn as a destructive action. Unblock restores something, so it isn't.
    var isDestructive: Bool {
        switch self {
        case .report, .block:                 return true
        case .mute, .unblock:                 return false
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
}
