//
//  ChatInviteCardCopy.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCore

/// The group-ready card's words for a style. The bubble names the group; the Group Money shell's
/// empty state sits under a header that already does (node 13729:642).
public struct ChatInviteCardCopy: Equatable, Sendable {

    public let title: String
    public let subtitle: String
    public let button: String

    public init(style: ChatInviteCardStyle, groupName: String) {
        switch style {
        case .incomingBubble:
            title = "Your Group Is Ready"
            subtitle = "Invite people to join \(groupName)"
        case .emptyState:
            title = "Your group is ready"
            subtitle = "Invite people to join your group."
        }
        button = "Invite People"
    }
}
