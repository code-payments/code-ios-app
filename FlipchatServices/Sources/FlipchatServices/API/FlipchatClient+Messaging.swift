//
//  FlipchatClient+Messaging.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import FlipchatAPI
import CodeServices

public typealias StreamMessagesReference = BidirectionalStreamReference<Flipchat_Messaging_V1_StreamMessagesRequest, Flipchat_Messaging_V1_StreamMessagesResponse>

extension FlipchatClient {
    
    public func streamMessages(chatID: ChatID, owner: KeyPair, completion: @escaping (Result<[Chat.Message], ErrorStreamMessages>) -> Void) -> StreamMessagesReference {
        messagingService.streamMessages(chatID: chatID, owner: owner, completion: completion)
    }
    
    public func sendMessage(chatID: ChatID, owner: KeyPair, content: Chat.Content) async throws -> Chat.Message {
        try await withCheckedThrowingContinuation { c in
            messagingService.sendMessage(chatID: chatID, owner: owner, content: content) { c.resume(with: $0) }
        }
    }
    
    public func fetchMessages(chatID: ChatID, owner: KeyPair, query: PageQuery = .init()) async throws -> [Chat.Message] {
        try await withCheckedThrowingContinuation { c in
            messagingService.fetchMessages(chatID: chatID, owner: owner, query: query) { c.resume(with: $0) }
        }
    }
    
    public func advancePointer(chatID: ChatID, to messageID: MessageID, owner: KeyPair) async throws {
        try await withCheckedThrowingContinuation { c in
            messagingService.advancePointer(chatID: chatID, to: messageID, owner: owner) { c.resume(with: $0) }
        }
    }
}
