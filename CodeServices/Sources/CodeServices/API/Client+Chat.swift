//
//  Client+Chat.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import CodeAPI

public typealias ChatMessageStreamReference = BidirectionalStreamReference<Code_Chat_V2_StreamChatEventsRequest, Code_Chat_V2_StreamChatEventsResponse>

extension Client {
    
    public func openChatStream(chatID: ChatID, memberID: MemberID, owner: KeyPair, completion: @escaping (Result<[Chat.Event], ErrorOpenChatStream>) -> Void) -> ChatMessageStreamReference {
        chatService.openChatStream(chatID: chatID, memberID: memberID, owner: owner, completion: completion)
    }
    
    public func fetchChats(owner: KeyPair) async throws -> [Chat] {
        try await withCheckedThrowingContinuation { c in
            chatService.fetchChats(owner: owner) { c.resume(with: $0) }
        }
    }
    
    public func startChat(owner: KeyPair, tipIntentID: PublicKey) async throws -> Chat {
        try await withCheckedThrowingContinuation { c in
            chatService.startChat(owner: owner, tipIntentID: tipIntentID) { c.resume(with: $0) }
        }
    }
    
    public func sendMessage(chatID: ChatID, memberID: MemberID, owner: KeyPair, content: Chat.Content) async throws -> Chat.Message {
        try await withCheckedThrowingContinuation { c in
            chatService.sendMessage(chatID: chatID, memberID: memberID, owner: owner, content: content) { c.resume(with: $0) }
        }
    }
    
    public func fetchMessages(chatID: ChatID, memberID: MemberID, owner: KeyPair, direction: MessageDirection = .ascending(from: nil), pageSize: Int) async throws -> [Chat.Message] {
        try await withCheckedThrowingContinuation { c in
            chatService.fetchMessages(chatID: chatID, memberID: memberID, owner: owner, direction: direction, pageSize: pageSize) { c.resume(with: $0) }
        }
    }
    
    public func advancePointer(chatID: ChatID, to messageID: ID, memberID: MemberID, owner: KeyPair) async throws {
        try await withCheckedThrowingContinuation { c in
            chatService.advancePointer(chatID: chatID, to: messageID, memberID: memberID, owner: owner) { c.resume(with: $0) }
        }
    }
    
    public func setMuteState(chatID: ChatID, muted: Bool, owner: KeyPair) async throws {
        try await withCheckedThrowingContinuation { c in
            chatService.setMuteState(chatID: chatID, muted: muted, owner: owner) { c.resume(with: $0) }
        }
    }
    
    public func setSubscriptionState(chatID: ChatID, subscribed: Bool, owner: KeyPair) async throws {
        try await withCheckedThrowingContinuation { c in
            chatService.setSubscriptionState(chatID: chatID, subscribed: subscribed, owner: owner) { c.resume(with: $0) }
        }
    }
}
