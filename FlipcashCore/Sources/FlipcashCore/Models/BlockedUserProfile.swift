//
//  BlockedUserProfile.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// A blocked user resolved to the fields the Blocked list shows: identity, when
/// they were blocked, their display name, and their avatar BlurHash.
public struct BlockedUserProfile: Identifiable, Hashable, Sendable {
    public let userID: UserID
    public let blockedAt: Date
    public var displayName: String
    public var avatarBlurhash: String?

    public var id: UserID { userID }

    public init(userID: UserID, blockedAt: Date, displayName: String, avatarBlurhash: String?) {
        self.userID = userID
        self.blockedAt = blockedAt
        self.displayName = displayName
        self.avatarBlurhash = avatarBlurhash
    }
}
