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
        
        public init(displayName: String?, avatarURL: URL?) {
            self.displayName = displayName
            self.avatarURL = avatarURL
        }
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

extension Chat.Identity {
    init(_ proto: Flipchat_Chat_V1_MemberIdentity) {
        self.init(
            displayName: proto.displayName.isEmpty ? nil : proto.displayName,
            avatarURL: proto.profilePicURL.isEmpty ? nil : URL(string: proto.profilePicURL)
        )
    }
}
