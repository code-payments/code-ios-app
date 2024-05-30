//
//  Client+Chat.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import CodeAPI

public typealias ChatMessageStreamReference = BidirectionalStreamReference<Code_Chat_V1_StreamChatEventsRequest, Code_Chat_V1_StreamChatEventsResponse>

extension Client {
    
    public func openChatStream(chatID: ID, owner: KeyPair, completion: @escaping (Result<[Chat.Message], Error>) -> Void) -> ChatMessageStreamReference {
        chatService.openChatStream(chatID: chatID, owner: owner, completion: completion)
    }
    
    public func fetchChats(owner: KeyPair) async throws -> [Chat] {
        try await withCheckedThrowingContinuation { c in
            chatService.fetchChats(owner: owner) { c.resume(with: $0) }
        }
    }
    
    public func fetchMessages(chatID: ID, owner: KeyPair, direction: MessageDirection = .ascending(from: nil), pageSize: Int) async throws -> [Chat.Message] {
        try await withCheckedThrowingContinuation { c in
            chatService.fetchMessages(chatID: chatID, owner: owner, direction: direction, pageSize: pageSize) { c.resume(with: $0) }
        }
    }
    
    public func advancePointer(chatID: ID, to messageID: ID, owner: KeyPair) async throws {
        try await withCheckedThrowingContinuation { c in
            chatService.advancePointer(chatID: chatID, to: messageID, owner: owner) { c.resume(with: $0) }
        }
    }
    
    public func setMuteState(chatID: ID, muted: Bool, owner: KeyPair) async throws {
        try await withCheckedThrowingContinuation { c in
            chatService.setMuteState(chatID: chatID, muted: muted, owner: owner) { c.resume(with: $0) }
        }
    }
    
    public func setSubscriptionState(chatID: ID, subscribed: Bool, owner: KeyPair) async throws {
        try await withCheckedThrowingContinuation { c in
            chatService.setSubscriptionState(chatID: chatID, subscribed: subscribed, owner: owner) { c.resume(with: $0) }
        }
    }
}
