//
//  Chat.Member.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import CodeAPI

extension Chat {
    public struct Member: Equatable, Identifiable, Hashable {
        
        /// Globally unique ID for this chat member
        public let id: MemberID
        
        /// Is this chat member yourself? This enables client to identify which member_id
        /// is themselves.
        public let isSelf: Bool
        
        /// The chat member's identity if it has been revealed.
        public var identity: Identity
        
        /// Chat message state for this member. This list will have DELIVERED and READ
        /// pointers, if they exist. SENT pointers should be inferred by persistence
        /// on server.
        public var pointers: [Pointer]
        
        /// Estimated number of unread messages for the chat member in this chat
        ///
        /// Only valid when is_self = true
        public var numUnread: Int

        /// Has the chat member muted this chat?
        ///
        /// Only valid when is_self = true
        public var isMuted: Bool

        /// Is the chat member subscribed to this chat?
        ///
        /// Only valid when is_self = true
        public var isSubscribed: Bool
        
        public init(id: ID, isSelf: Bool, identity: Identity, pointers: [Pointer], numUnread: Int, isMuted: Bool, isSubscribed: Bool) {
            self.id = id
            self.isSelf = isSelf
            self.identity = identity
            self.pointers = pointers
            self.numUnread = numUnread
            self.isMuted = isMuted
            self.isSubscribed = isSubscribed
        }
    }
}

extension Chat.Member {
    public enum Identity: Equatable, Hashable {
        
        case unknown(String)
        case twitter(String)
        
        public var isKnown: Bool {
            switch self {
            case .unknown:
                return false
            case .twitter:
                return true
            }
        }
        
        public var name: String? {
            let name: String
            
            switch self {
            case .unknown(let n): name = n
            case .twitter(let n): name = n
            }
            
            return !name.isEmpty ? name : nil
        }
    }
}

// MARK: - Proto -

extension Chat.Member {
    init(_ proto: Code_Chat_V2_ChatMember) {
        self.init(
            id: .init(data: proto.memberID.value),
            isSelf: proto.isSelf,
            identity: .init(proto.identity),
            pointers: proto.pointers.map { .init($0) },
            numUnread: Int(proto.numUnread),
            isMuted: proto.isMuted,
            isSubscribed: proto.isSubscribed
        )
    }
}

extension Chat.Member.Identity {
    init(_ proto: Code_Chat_V2_ChatMemberIdentity) {
        switch proto.platform {
        case .unknownPlatform:
            self = .unknown(proto.username)
        case .twitter:
            self = .twitter(proto.username)
        case .UNRECOGNIZED:
            self = .unknown(proto.username)
        }
    }
}
