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
        
        public let title: String?
        public let unreadCount: Int
        public let hasMoreUnread: Bool
        
        public let isMuted: Bool
        public let canMute: Bool
        
        public var formattedTitle: String {
            if let title {
                return "\(roomNumber.formattedRoomNumberShort): \(title)"
            } else {
                return roomNumber.formattedRoomNumber
            }
        }
        
        public init(id: ChatID, kind: Kind, roomNumber: RoomNumber, ownerUser: UserID, coverAmount: Kin, title: String?, unreadCount: Int, hasMoreUnread: Bool, isMuted: Bool, canMute: Bool) {
            self.id = id
            self.kind = kind
            self.roomNumber = roomNumber
            self.ownerUser = ownerUser
            self.coverAmount = coverAmount
            self.title = title
            self.unreadCount = unreadCount
            self.hasMoreUnread = hasMoreUnread
            self.isMuted = isMuted
            self.canMute = canMute
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
            title: proto.displayName.isEmpty ? nil : proto.displayName,
            unreadCount: Int(proto.numUnread),
            hasMoreUnread: proto.hasMoreUnread_p,
            isMuted: !proto.isPushEnabled,
            canMute: proto.canDisablePush
        )
    }
}

extension Int {
    
    /// Unread count with more unread is encoded as a negative value
    public func encodingUnreadCount(hasMore: Bool) -> Int {
        if hasMore {
            return -self
        } else {
            return self
        }
    }
    
    /// Unread count with more unread is encoded as a negative value
    public func decodingUnreadCount() -> (count: Int, hasMore: Bool) {
        if self < 0 {
            return (-self, true)
        } else {
            return (self, false)
        }
    }
}
