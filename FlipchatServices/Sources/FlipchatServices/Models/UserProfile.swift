//
//  UserProfile.swift
//  FlipchatServices
//
//  Created by Dima Bart on 2025-02-26.
//

import Foundation
import FlipchatAPI

public struct UserProfile: Hashable, Equatable, Sendable {
    public let displayName: String
    public let socialProfile: Chat.SocialProfile?
}

// MARK: - Proto -

extension UserProfile {
    init(_ proto: Flipchat_Profile_V1_UserProfile) {
        self.init(
            displayName: proto.displayName,
            socialProfile: .init(proto.socialProfiles.first)
        )
    }
}
