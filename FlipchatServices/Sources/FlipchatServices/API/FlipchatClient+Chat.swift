//
//  FlipchatClient+Chat.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import FlipchatAPI

public typealias StreamChatsReference = BidirectionalStreamReference<Flipchat_Chat_V1_StreamChatEventsRequest, Flipchat_Chat_V1_StreamChatEventsResponse>

extension FlipchatClient {
    
    public func streamChatEvents(owner: KeyPair, completion: @escaping (Result<[Chat.BatchUpdate], ErrorStreamChatEvents>) -> Void) -> StreamChatsReference {
        chatService.streamChatEvents(owner: owner, completion: completion)
    }
    
    public func startGroupChat(with users: [UserID], owner: KeyPair) async throws -> Chat.Metadata {
        try await withCheckedThrowingContinuation { c in
            chatService.startGroupChat(with: users, owner: owner) { c.resume(with: $0) }
        }
    }
    
    public func joinGroupChat(chatID: ChatID, intentID: PublicKey?, owner: KeyPair) async throws -> (Chat.Metadata, [Chat.Member]) {
        try await withCheckedThrowingContinuation { c in
            chatService.joinGroupChat(chatID: chatID, intentID: intentID, owner: owner) { c.resume(with: $0) }
        }
    }
    
    public func leaveChat(chatID: ChatID, owner: KeyPair) async throws {
        try await withCheckedThrowingContinuation { c in
            chatService.leaveChat(chatID: chatID, owner: owner) { c.resume(with: $0) }
        }
    }
    
    public func fetchChats(owner: KeyPair, query: PageQuery = .init()) async throws -> [Chat.Metadata] {
        try await withCheckedThrowingContinuation { c in
            chatService.fetchChats(owner: owner, query: query) { c.resume(with: $0) }
        }
    }
    
    public func fetchChat(for identifier: ChatIdentifier, owner: KeyPair) async throws -> (Chat.Metadata, [Chat.Member]) {
        try await withCheckedThrowingContinuation { c in
            chatService.fetchChat(for: identifier, owner: owner) { c.resume(with: $0) }
        }
    }
}
