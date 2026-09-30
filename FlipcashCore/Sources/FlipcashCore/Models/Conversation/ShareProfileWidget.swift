//
//  ShareProfileWidget.swift
//  FlipcashCore
//

import Foundation
import FlipcashAPI

/// A widget message that shares a user's profile. See `messaging.v1.ShareProfileWidget`.
public struct ShareProfileWidget: Hashable, Sendable {

    /// The handle of the profile being shared.
    public let username: Username

    public init(username: Username) {
        self.username = username
    }
}

extension ShareProfileWidget {

    /// Returns nil when `proto` carries no well-formed username.
    init?(_ proto: Flipcash_Messaging_V1_ShareProfileWidget) {
        guard let username = Username(proto.username) else { return nil }
        self.username = username
    }

    var proto: Flipcash_Messaging_V1_ShareProfileWidget {
        .with { $0.username = username.proto }
    }
}

extension Flipcash_Messaging_V1_WidgetContent {

    /// The profile share this widget carries, or nil for any variant this
    /// client doesn't recognize — callers treat that as unsupported content.
    var shareProfile: ShareProfileWidget? {
        switch type {
        case .shareProfile(let widget): ShareProfileWidget(widget)
        case nil:                       nil
        }
    }
}
