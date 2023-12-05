//
//  Client+Chat.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

extension Client {
    
    public func fetchChats(owner: KeyPair) async throws -> [Chat] {
        try await withCheckedThrowingContinuation { c in
            chatService.fetchChats(owner: owner) { c.resume(with: $0) }
        }
    }
    
    public func fetchMessages(chatID: ID, owner: KeyPair) async throws -> [Chat.Message] {
        try await withCheckedThrowingContinuation { c in
            chatService.fetchMessages(chatID: chatID, owner: owner) { c.resume(with: $0) }
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
}
