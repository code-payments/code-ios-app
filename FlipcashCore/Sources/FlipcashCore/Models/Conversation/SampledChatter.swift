//
//  SampledChatter.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI

/// A recent chatter in a public group, as `Chat.SampleChatters` reports it: the public alternative
/// to the members-only roster for a view whose viewer is not a member (preview, lobby).
public struct SampledChatter: Sendable, Equatable {
    public let userID: UserID
    /// Their public profile.
    public let profile: Profile
    /// When they last sent a message in the chat, or `nil` when the server reports none.
    public let lastSentAt: Date?
    /// Whether they created the group.
    public let isCreator: Bool

    public init(userID: UserID, profile: Profile, lastSentAt: Date?, isCreator: Bool) {
        self.userID = userID
        self.profile = profile
        self.lastSentAt = lastSentAt
        self.isCreator = isCreator
    }
}

extension SampledChatter {
    /// `nil` for a chatter without a readable profile or user id, which the contract says the
    /// server always sets.
    init?(_ proto: Flipcash_Chat_V1_SampledChatter) {
        guard
            proto.hasUserProfile,
            let profile = try? Profile(proto.userProfile),
            let userID = profile.userID
        else { return nil }
        self.init(
            userID: userID,
            profile: profile,
            lastSentAt: proto.hasLastSentAt ? proto.lastSentAt.date : nil,
            isCreator: proto.isCreator
        )
    }
}
