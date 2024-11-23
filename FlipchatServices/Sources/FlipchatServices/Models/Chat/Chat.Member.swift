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
        
        /// Globally unique ID for this chat member
        public let id: UserID
        
        /// Is this chat member yourself? This enables client to identify which member_id
        /// is themselves.
        public let isSelf: Bool
        
        /// Is this chat member the host of the chat
        public let isHost: Bool
        
        /// Is this user allowed to send messages
        public let isMuted: Bool
        
        /// The chat member's identity if it has been revealed.
        public var identity: Identity
        
        /// Chat message state for this member. This list will have DELIVERED and READ
        /// pointers, if they exist. SENT pointers should be inferred by persistence
        /// on server.
        public var pointers: [Pointer]
        
        public init(id: ID, isSelf: Bool, isHost: Bool, isMuted: Bool, identity: Identity, pointers: [Pointer]) {
            self.id = id
            self.isSelf = isSelf
            self.isHost = isHost
            self.isMuted = isMuted
            self.identity = identity
            self.pointers = pointers
        }
    }
}

extension Chat.Member {
    public struct Identity: Equatable, Hashable, Sendable {
        
        public var displayName: String
        public var avatarURL: URL?
        
        init(displayName: String, avatarURL: URL?) {
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
            isHost: proto.isHost,
            isMuted: proto.isMuted,
            identity: .init(proto.identity),
            pointers: proto.pointers.map { .init($0) }
        )
    }
}

extension Chat.Member.Identity {
    init(_ proto: Flipchat_Chat_V1_MemberIdentity) {
        self.init(
            displayName: proto.displayName.isEmpty ? "Member" : proto.displayName,
            avatarURL: URL(string: proto.profilePicURL)
        )
    }
}
