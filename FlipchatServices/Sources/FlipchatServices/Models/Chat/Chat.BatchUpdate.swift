//
//  StreamEvent.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import FlipchatAPI

extension Chat {
    public struct BatchUpdate: Sendable {
        
        public var chatID: ChatID
        public var chatUpdates: [ChatUpdate]
        public var lastMessage: Chat.Message?
        public var memberUpdates: [MemberUpdate]
        public var typingUpdate: TypingUpdate?
        
        public struct TypingUpdate: Sendable {
            var userID: UserID
            var isTyping: Bool
        }
        
        public enum ChatUpdate: Sendable {
            case fullRefresh(Chat.Metadata)
            case unreadCount(Int, Bool) // count, hasMore
            case displayName(String)
            case coverCharge(Kin)
            case lastActivity(Date)
            case openStateChanged(Bool)
        }
        
        public enum MemberUpdate: Sendable {
            case fullRefresh([Chat.Member])
            case invidualRefresh(Chat.Member)
            case joined(Chat.Member)
            case left(UserID)
            case removed(UserID)
            case muted(UserID)
            case promoted(UserID)
            case demoted(UserID)
            case identityChanged(UserID, Chat.Identity?)
        }
    }
}

extension Chat.BatchUpdate {
    
    public init?(_ proto: Flipchat_Chat_V1_StreamChatEventsResponse.ChatUpdate) {
        guard proto.hasChatID else {
            return nil
        }
        
        self.init(
            chatID: ChatID(data: proto.chatID.value),
            chatUpdates: proto.metadataUpdates.compactMap { ChatUpdate($0) },
            lastMessage: proto.hasLastMessage ? Chat.Message(proto.lastMessage) : nil,
            memberUpdates: proto.memberUpdates.compactMap { MemberUpdate($0) },
            typingUpdate: proto.hasIsTyping ? TypingUpdate(proto.isTyping) : nil
        )
    }
}


extension Chat.BatchUpdate.TypingUpdate {
    public init?(_ proto: Flipchat_Messaging_V1_IsTyping) {
        guard proto.hasUserID else {
            return nil
        }
        
        self.init(
            userID: UserID(data: proto.userID.value),
            isTyping: proto.isTyping
        )
    }
}

//extension Chat.BatchUpdate.PointerUpdate {
//    public init?(_ proto: Flipchat_Chat_V1_StreamChatEventsResponse.ChatUpdate.PointerUpdate) {
//        guard proto.hasMember else {
//            return nil
//        }
//        
//        self.init(
//            userID: UserID(data: proto.member.value),
//            pointer: Chat.Pointer(proto.pointer)
//        )
//    }
//}

extension Chat.BatchUpdate.ChatUpdate {
    public init?(_ proto: Flipchat_Chat_V1_MetadataUpdate) {
        guard let kind = proto.kind else {
            return nil
        }
        
        switch kind {
        case .fullRefresh(let update):
            self = .fullRefresh(Chat.Metadata(update.metadata))
            
        case .unreadCountChanged(let update):
            self = .unreadCount(Int(update.numUnread), update.hasMoreUnread_p)
            
        case .displayNameChanged(let update):
            self = .displayName(update.newDisplayName)
            
        case .messagingFeeChanged(let update):
            self = .coverCharge(Kin(quarks: update.newMessagingFee.quarks))
            
        case .lastActivityChanged(let update):
            self = .lastActivity(update.newLastActivity.date)
            
        case .openStatusChanged(let update):
            self = .openStateChanged(update.newOpenStatus.isCurrentlyOpen)
        }
    }
}

extension Chat.BatchUpdate.MemberUpdate {
    public init?(_ proto: Flipchat_Chat_V1_MemberUpdate) {
        guard let kind = proto.kind else {
            return nil
        }
        
        switch kind {
        case .fullRefresh(let update):
            self = .fullRefresh(update.members.map { Chat.Member($0) })
            
        case .individualRefresh(let update):
            self = .invidualRefresh(Chat.Member(update.member))
            
        case .joined(let update):
            self = .joined(Chat.Member(update.member))
            
        case .left(let update):
            self = .left(UserID(data: update.member.value))
            
        case .removed(let update):
            self = .removed(UserID(data: update.member.value))
            
        case .muted(let update):
            self = .muted(UserID(data: update.member.value))
            
        case .promoted(let update):
            self = .promoted(UserID(data: update.member.value))
            
        case .demoted(let update):
            self = .demoted(UserID(data: update.member.value))
            
        case .identityChanged(let update):
            self = .identityChanged(
                UserID(data: update.member.value),
                update.hasNewIdentity ? Chat.Identity(update.newIdentity) : nil
            )
        }
    }
}
