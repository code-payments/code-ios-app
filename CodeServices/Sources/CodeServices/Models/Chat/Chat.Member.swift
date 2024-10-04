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
    public struct Member: Equatable, Identifiable, Hashable, Sendable {
        
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
        
        public init(id: ID, isSelf: Bool, identity: Identity, pointers: [Pointer]) {
            self.id = id
            self.isSelf = isSelf
            self.identity = identity
            self.pointers = pointers
        }
    }
}

extension Chat.Member {
    public enum Identity: Equatable, Hashable, Sendable {
        
        case unknown(String)
        case twitter(String, URL?)
        
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
            case .twitter(let n, _): name = n
            }
            
            return !name.isEmpty ? name : nil
        }
        
        public var avatarURL: URL? {
            switch self {
            case .unknown:
                return nil
            case .twitter(_, let url):
                return url
            }
        }
    }
}

// MARK: - Proto -

extension Chat.Member {
    init(_ proto: Code_Chat_V2_Member) {
        self.init(
            id: .init(data: proto.memberID.value),
            isSelf: proto.isSelf,
            identity: .init(proto.identity),
            pointers: proto.pointers.map { .init($0) }
        )
    }
}

extension Chat.Member.Identity {
    init(_ proto: Code_Chat_V2_MemberIdentity) {
        switch proto.platform {
        case .unknownPlatform:
            self = .unknown(proto.username)
        case .twitter:
            self = .twitter(proto.username, URL(string: proto.profilePicURL))
        case .UNRECOGNIZED:
            self = .unknown(proto.username)
        }
    }
}
