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
    
    public func openChatStream(chatID: ChatID, owner: KeyPair, completion: @escaping (Result<[ChatLegacy.Event], ErrorOpenChatStream>) -> Void) -> ChatMessageStreamReference {
        chatService.openChatStream(chatID: chatID, owner: owner, completion: completion)
    }
    
    public func fetchChats(owner: KeyPair) async throws -> [ChatLegacy] {
        try await withCheckedThrowingContinuation { c in
            chatService.fetchChats(owner: owner) { c.resume(with: $0) }
        }
    }
    
    public func startChat(owner: KeyPair, intentID: PublicKey, destination: PublicKey) async throws -> ChatLegacy {
        try await withCheckedThrowingContinuation { c in
            chatService.startChat(owner: owner, intentID: intentID, destination: destination) { c.resume(with: $0) }
        }
    }
    
    public func sendMessage(chatID: ChatID, owner: KeyPair, content: ChatLegacy.Content) async throws -> ChatLegacy.Message {
        try await withCheckedThrowingContinuation { c in
            chatService.sendMessage(chatID: chatID, owner: owner, content: content) { c.resume(with: $0) }
        }
    }
    
    public func fetchMessages(chatID: ChatID, memberID: MemberID, owner: KeyPair, direction: MessageDirection = .ascending(from: nil), pageSize: Int) async throws -> [ChatLegacy.Message] {
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
}
