//
//  FlipchatClient+Chat.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import FlipchatAPI
import CodeServices

//public typealias StreamMessagesReference = BidirectionalStreamReference<Flipchat_Messaging_V1_StreamMessagesRequest, Flipchat_Messaging_V1_StreamMessagesResponse>

extension FlipchatClient {
    
    public func startGroupChat(with userID: UserID? = nil, owner: KeyPair) async throws -> Chat {
        try await withCheckedThrowingContinuation { c in
            chatService.startGroupChat(with: userID, owner: owner) { c.resume(with: $0) }
        }
    }
    
    public func fetchChats(for userID: UserID, owner: KeyPair, query: PageQuery = .init()) async throws -> [Chat] {
        try await withCheckedThrowingContinuation { c in
            chatService.fetchChats(for: userID, owner: owner, query: query) { c.resume(with: $0) }
        }
    }
    
    public func fetchChat(for roomNumber: RoomNumber, owner: KeyPair) async throws -> Chat {
        try await withCheckedThrowingContinuation { c in
            chatService.fetchChat(for: roomNumber, owner: owner) { c.resume(with: $0) }
        }
    }
}
