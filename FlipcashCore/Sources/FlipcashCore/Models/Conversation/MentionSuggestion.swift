//
//  MentionSuggestion.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI

/// One person the server suggests after an `@` in a group chat, from `Chat.GetMentionSuggestions`.
public struct MentionSuggestion: Sendable, Equatable {
    public let userID: UserID
    /// Their public profile, which always carries a username.
    public let profile: Profile
    /// When they last sent a message in the chat as the server recorded it, or `nil` when they are
    /// suggested for another reason.
    public let lastSentAt: Date?

    public init(userID: UserID, profile: Profile, lastSentAt: Date?) {
        self.userID = userID
        self.profile = profile
        self.lastSentAt = lastSentAt
    }

    /// The suggestion as a roster member, for the views that draw one.
    public var member: ConversationMember {
        ConversationMember(
            userID: userID,
            displayName: profile.displayName ?? "",
            profilePicture: profile.profilePicture,
            username: profile.username
        )
    }
}

extension MentionSuggestion {
    /// `nil` for a suggestion without a readable user id or username, both of which the contract
    /// says the server always sets: a pick inserts the username, so one without it is unusable.
    init?(_ proto: Flipcash_Chat_V1_MentionSuggestion) {
        guard
            proto.hasUserProfile,
            let profile = try? Profile(proto.userProfile),
            let userID = profile.userID,
            profile.username != nil
        else { return nil }
        self.init(
            userID: userID,
            profile: profile,
            lastSentAt: proto.hasLastSentAt ? proto.lastSentAt.date : nil
        )
    }
}
