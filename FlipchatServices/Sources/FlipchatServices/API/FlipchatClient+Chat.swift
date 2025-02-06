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
    
    public func startGroupChat(with users: [UserID], intentID: PublicKey, owner: KeyPair) async throws -> ChatDescription {
        try await withCheckedThrowingContinuation { c in
            chatService.startGroupChat(with: users, intentID: intentID, owner: owner) { c.resume(with: $0) }
        }
    }
    
    public func joinGroupChat(chatID: ChatID, intentID: PublicKey?, owner: KeyPair) async throws -> ChatDescription {
        try await withCheckedThrowingContinuation { c in
            chatService.joinGroupChat(chatID: chatID, intentID: intentID, owner: owner) { c.resume(with: $0) }
        }
    }
    
    public func leaveChat(chatID: ChatID, owner: KeyPair) async throws {
        try await withCheckedThrowingContinuation { c in
            chatService.leaveChat(chatID: chatID, owner: owner) { c.resume(with: $0) }
        }
    }
    
    public func removeUser(userID: UserID, chatID: ChatID, owner: KeyPair) async throws {
        try await withCheckedThrowingContinuation { c in
            chatService.removeUser(userID: userID, chatID: chatID, owner: owner) { c.resume(with: $0) }
        }
    }
    
    public func muteUser(userID: UserID, chatID: ChatID, owner: KeyPair) async throws {
        try await withCheckedThrowingContinuation { c in
            chatService.muteUser(userID: userID, chatID: chatID, owner: owner) { c.resume(with: $0) }
        }
    }
    
    public func muteChat(chatID: ChatID, muted: Bool, owner: KeyPair) async throws {
        try await withCheckedThrowingContinuation { c in
            chatService.muteChat(chatID: chatID, muted: muted, owner: owner) { c.resume(with: $0) }
        }
    }
    
    public func reportMessage(userID: UserID, messageID: MessageID, owner: KeyPair) async throws {
        try await withCheckedThrowingContinuation { c in
            chatService.reportMessage(userID: userID, messageID: messageID, owner: owner) { c.resume(with: $0) }
        }
    }
    
    public func fetchChats(owner: KeyPair) async throws -> [Chat.Metadata] {
        try await withCheckedThrowingContinuation { c in
            chatService.fetchChats(owner: owner) { c.resume(with: $0) }
        }
    }
    
    public func fetchChat(for identifier: ChatIdentifier, owner: KeyPair) async throws -> ChatDescription {
        try await withCheckedThrowingContinuation { c in
            chatService.fetchChat(for: identifier, owner: owner) { c.resume(with: $0) }
        }
    }
    
    public func changeCover(chatID: ChatID, newCover: Kin, owner: KeyPair) async throws {
        try await withCheckedThrowingContinuation { c in
            chatService.changeCover(chatID: chatID, newCover: newCover, owner: owner) { c.resume(with: $0) }
        }
    }
    
    public func setMessageFee(chatID: ChatID, newFee: Kin, owner: KeyPair) async throws {
        try await withCheckedThrowingContinuation { c in
            chatService.setMessageFee(chatID: chatID, newFee: newFee, owner: owner) { c.resume(with: $0) }
        }
    }
    
    public func changeRoomName(chatID: ChatID, newName: String, owner: KeyPair) async throws {
        try await withCheckedThrowingContinuation { c in
            chatService.changeRoomName(chatID: chatID, newName: newName, owner: owner) { c.resume(with: $0) }
        }
    }
    
    public func openRoom(chatID: ChatID, owner: KeyPair) async throws {
        try await withCheckedThrowingContinuation { c in
            chatService.openRoom(chatID: chatID, owner: owner) { c.resume(with: $0) }
        }
    }
    
    public func closeRoom(chatID: ChatID, owner: KeyPair) async throws {
        try await withCheckedThrowingContinuation { c in
            chatService.closeRoom(chatID: chatID, owner: owner) { c.resume(with: $0) }
        }
    }
    
    public func promoteUser(chatID: ChatID, userID: UserID, owner: KeyPair) async throws {
        try await withCheckedThrowingContinuation { c in
            chatService.promoteUser(chatID: chatID, userID: userID, owner: owner) { c.resume(with: $0) }
        }
    }
    
    public func demoteUser(chatID: ChatID, userID: UserID, owner: KeyPair) async throws {
        try await withCheckedThrowingContinuation { c in
            chatService.demoteUser(chatID: chatID, userID: userID, owner: owner) { c.resume(with: $0) }
        }
    }
}
