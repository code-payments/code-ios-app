//
//  FlipchatClient+Messaging.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import FlipchatAPI

public typealias StreamMessagesReference = BidirectionalStreamReference<Flipchat_Messaging_V1_StreamMessagesRequest, Flipchat_Messaging_V1_StreamMessagesResponse>

extension FlipchatClient {
    
    public func streamMessages(chatID: ChatID, from messageID: MessageID?, owner: KeyPair, completion: @escaping (Result<[Chat.Message], ErrorStreamMessages>) -> Void) -> StreamMessagesReference {
        messagingService.streamMessages(chatID: chatID, from: messageID, owner: owner, completion: completion)
    }
    
    public func sendMessage(chatID: ChatID, owner: KeyPair, text: String, replyingTo: MessageID? = nil) async throws -> Chat.Message {
        try await withCheckedThrowingContinuation { c in
            messagingService.sendMessage(chatID: chatID, owner: owner, text: text, replyingTo: replyingTo) { c.resume(with: $0) }
        }
    }
    
    public func fetchMessages(chatID: ChatID, owner: KeyPair, query: PageQuery = .init()) async throws -> [Chat.Message] {
        try await withCheckedThrowingContinuation { c in
            messagingService.fetchMessages(chatID: chatID, owner: owner, query: query) { c.resume(with: $0) }
        }
    }
    
    public func advanceReadPointer(chatID: ChatID, to messageID: MessageID, owner: KeyPair) async throws {
        try await withCheckedThrowingContinuation { c in
            messagingService.advanceReadPointer(chatID: chatID, to: messageID, owner: owner) { c.resume(with: $0) }
        }
    }
}
