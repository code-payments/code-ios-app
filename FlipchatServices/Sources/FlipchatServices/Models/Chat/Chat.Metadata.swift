//
//  Chat.Metadata.swift
//  FlipchatServices
//
//  Created by Dima Bart on 2024-10-28.
//

import Foundation
import FlipchatAPI

extension Chat {
    public struct Metadata: Hashable, Equatable, Identifiable, Sendable {
            
        public let id: ChatID
        public let kind: Kind
        public let roomNumber: RoomNumber
        public let ownerUser: UserID
        public let coverAmount: Kin
        
        public var title: String
        public var unreadCount: Int
        
        public init(id: ChatID, kind: Kind, roomNumber: RoomNumber, ownerUser: UserID, coverAmount: Kin, title: String, unreadCount: Int) {
            self.id = id
            self.kind = kind
            self.roomNumber = roomNumber
            self.ownerUser = ownerUser
            self.coverAmount = coverAmount
            self.title = title
            self.unreadCount = unreadCount
        }
    }
}

// MARK: - Kind -

extension Chat {
    public enum Kind: Int, Hashable, Equatable, Sendable {
        case unknown
        case twoWay
        case group
    }
}

// MARK: - Description -

extension Chat.Metadata: CustomDebugStringConvertible, CustomStringConvertible {
    
    nonisolated
    public var description: String {
        "Chat:\(id.data.hexEncodedString())"
    }
    
    nonisolated
    public var debugDescription: String {
        description
    }
}

// MARK: - Proto -

extension Chat.Metadata {
    public init(_ proto: Flipchat_Chat_V1_Metadata) {
        self.init(
            id: .init(data: proto.chatID.value),
            kind: .init(rawValue: proto.type.rawValue) ?? .unknown,
            roomNumber: proto.roomNumber,
            ownerUser: UserID(data: proto.owner.value),
            coverAmount: Kin(quarks: proto.coverCharge.quarks),
            title: proto.title,
            unreadCount: Int(proto.numUnread)
        )
    }
}
