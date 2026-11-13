//
//  ChatInviteCardCopy.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// How the group-ready card is drawn at the head of a group's transcript.
public enum ChatInviteCardStyle: Equatable, Sendable {
    /// Today's card: an incoming bubble from Flipcash.
    case incomingBubble
    /// A centred title, line and button with no bubble.
    case emptyState
}

/// The group-ready card's words for a style.
public struct ChatInviteCardCopy: Equatable, Sendable {

    public let title: String
    public let subtitle: String
    public let button: String

    public init(style: ChatInviteCardStyle, groupName: String) {
        title = "Your Group Is Ready"
        subtitle = "Invite people to join \(groupName)"
        button = "Invite People"
    }
}
