//
//  NotificationNameStyle.swift
//  FlipcashCore
//

import FlipcashAPI

/// How a push's contact substitution renders the resolved name.
public enum NotificationNameStyle {
    /// The contact's full name (e.g. "Katie Tonin").
    case full
    /// The contact's given name only (e.g. "Katie").
    case firstOnly
}

extension Flipcash_Push_V1_Payload.Category {
    /// The name style applied to this category's contact substitutions.
    public var nameStyle: NotificationNameStyle {
        switch self {
        case .contactJoin: .full
        case .chat: .firstOnly
        case .default, .depositWithdrawal, .buySell, .gain, .UNRECOGNIZED: .full
        }
    }
}
