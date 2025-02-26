//
//  ChatLegacy.Member.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import FlipchatAPI

extension Chat {
    public struct Member: Equatable, Identifiable, Hashable, Sendable {
        
        public let id: UserID
        public let isSelf: Bool
        public let isMuted: Bool
        public let hasModeratorPermission: Bool
        public let hasSendPermission: Bool
        public var identity: Identity
        public var pointers: [Pointer]
        
        public init(id: UserID, isSelf: Bool, isMuted: Bool, hasModeratorPermission: Bool, hasSendPermission: Bool, identity: Identity, pointers: [Pointer]) {
            self.id = id
            self.isSelf = isSelf
            self.isMuted = isMuted
            self.hasModeratorPermission = hasModeratorPermission
            self.hasSendPermission = hasSendPermission
            self.identity = identity
            self.pointers = pointers
        }
    }
}

extension Chat {
    public struct Identity: Equatable, Hashable, Sendable {
        
        public var displayName: String?
        public var avatarURL: URL?
        public let socialProfile: SocialProfile?
        
        public init(displayName: String?, avatarURL: URL?, socialProfile: SocialProfile?) {
            self.displayName = displayName
            self.avatarURL = avatarURL
            self.socialProfile = socialProfile
        }
    }
}

extension Chat {
    public struct SocialProfile: Equatable, Identifiable, Hashable, Sendable {
        
        public let kind: Kind
        public let id: String
        public let username: String
        public let displayName: String
        public let bio: String
        public let avatarURL: URL?
        public let verificationType: VerificationType
        public let followerCount: Int
        
        public init(kind: Kind, id: String, username: String, displayName: String, bio: String, avatarURL: URL?, verificationType: VerificationType, followerCount: Int) {
            self.kind = kind
            self.id = id
            self.username = username
            self.displayName = displayName
            self.bio = bio
            self.avatarURL = avatarURL
            self.verificationType = verificationType
            self.followerCount = followerCount
        }
    }
}

extension Chat.SocialProfile {
    public enum Kind: Int, Equatable, Hashable, Sendable {
        case twitter
    }
}

extension Chat.SocialProfile {
    public enum VerificationType: Int, Equatable, Hashable, Sendable {
        case none
        case blue
        case business
        case government
    }
}

// MARK: - Proto -

extension Chat.Member {
    init(_ proto: Flipchat_Chat_V1_Member) {
        self.init(
            id: .init(data: proto.userID.value),
            isSelf: proto.isSelf,
            isMuted: proto.isMuted,
            hasModeratorPermission: proto.hasModeratorPermission_p,
            hasSendPermission: proto.hasSendPermission_p,
            identity: .init(proto.identity),
            pointers: proto.pointers.map { .init($0) }
        )
    }
}

extension Chat.SocialProfile {
    init?(_ proto: Flipchat_Profile_V1_SocialProfile?) {
        switch proto?.type {
        case .x(let profile):
            self.init(
                kind: .twitter,
                id: profile.id,
                username: profile.username,
                displayName: profile.name,
                bio: profile.description_p,
                avatarURL: URL(string: profile.profilePicURL),
                verificationType: VerificationType(rawValue: profile.verifiedType.rawValue) ?? .none,
                followerCount: Int(profile.followerCount)
            )
            
        case .none:
            return nil
        }
    }
}

extension Chat.Identity {
    init(_ proto: Flipchat_Chat_V1_MemberIdentity) {
        self.init(
            displayName: proto.displayName.isEmpty ? nil : proto.displayName,
            avatarURL: proto.profilePicURL.isEmpty ? nil : URL(string: proto.profilePicURL),
            socialProfile: .init(proto.socialProfiles.first)
        )
    }
}
