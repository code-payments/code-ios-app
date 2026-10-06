//
//  ProfileMenuItems.swift
//  Flipcash
//

nonisolated enum ProfileMenuItem: Equatable {
    case mute
    case unmute
    case report
    case block
    case unblock

    var title: String {
        switch self {
        case .mute:    return "Mute"
        case .unmute:  return "Unmute"
        case .report:  return "Report"
        case .block:   return "Block"
        case .unblock: return "Unblock"
        }
    }

    var systemImage: String {
        switch self {
        case .mute:    return "bell.slash"
        case .unmute:  return "bell"
        case .report:  return "flag"
        case .block:   return "nosign"
        case .unblock: return "checkmark.circle"
        }
    }

    /// Whether the entry is drawn as a destructive action. Unblock restores something, so it isn't.
    var isDestructive: Bool {
        switch self {
        case .report, .block:                 return true
        case .mute, .unmute, .unblock:        return false
        }
    }
}

/// The entries of another user's overflow menu.
nonisolated enum ProfileMenuItems {

    /// Mute and Unmute need a DM to silence and are hidden while blocked, since the DM is hidden too.
    static func resolve(isBlocked: Bool, hasDM: Bool, isMuted: Bool) -> [ProfileMenuItem] {
        if isBlocked { return [.report, .unblock] }
        var items: [ProfileMenuItem] = []
        if hasDM { items.append(isMuted ? .unmute : .mute) }
        items.append(contentsOf: [.report, .block])
        return items
    }
}
