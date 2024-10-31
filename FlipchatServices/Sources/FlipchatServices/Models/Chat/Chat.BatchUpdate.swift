//
//  StreamEvent.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import CodeServices
import FlipchatAPI

extension Chat {
    public struct BatchUpdate {
        
        public var chatID: ChatID
        public var chatMetadata: Chat.Metadata?
        public var lastMessage: Chat.Message?
        public var memberUpdate: [Chat.Member]?
        public var pointerUpdate: PointerUpdate?
        public var typingUpdate: TypingUpdate?
        
        public struct TypingUpdate {
            var userID: UserID
            var isTyping: Bool
        }
        
        public struct PointerUpdate {
            var userID: UserID
            var pointer: Pointer
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
            chatMetadata: proto.hasMetadata ? Chat.Metadata(proto.metadata) : nil,
            lastMessage: proto.hasLastMessage ? Chat.Message(proto.lastMessage) : nil,
            memberUpdate: proto.memberUpdate.refresh.members.map { Chat.Member($0) },
            pointerUpdate: proto.hasPointer ? PointerUpdate(proto.pointer) : nil,
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

extension Chat.BatchUpdate.PointerUpdate {
    public init?(_ proto: Flipchat_Chat_V1_StreamChatEventsResponse.ChatUpdate.PointerUpdate) {
        guard proto.hasMember else {
            return nil
        }
        
        self.init(
            userID: UserID(data: proto.member.value),
            pointer: Chat.Pointer(proto.pointer)
        )
    }
}
