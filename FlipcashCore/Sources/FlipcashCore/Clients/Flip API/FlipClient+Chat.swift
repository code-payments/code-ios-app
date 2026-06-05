//
//  FlipClient+Chat.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

extension FlipClient {

    /// Page the DM chat feed to exhaustion against a single pinned snapshot.
    /// The caller must already be consuming `eventStreamer.events` so updates
    /// that land mid-pagination aren't lost.
    public func getDmChatFeed(owner: KeyPair) async throws -> [Conversation] {
        var all: [Conversation] = []
        var pagingToken: Data?

        while true {
            let page = try await withCheckedThrowingContinuation { c in
                chatService.getDmChatFeed(owner: owner, pagingToken: pagingToken) { c.resume(with: $0) }
            }
            all.append(contentsOf: page.chats)
            if !page.hasMore { break }
            pagingToken = page.pagingToken
        }

        return all
    }

    public func getChat(owner: KeyPair, chatID: ChatID) async throws -> Conversation {
        try await withCheckedThrowingContinuation { c in
            chatService.getChat(owner: owner, chatID: chatID) { c.resume(with: $0) }
        }
    }

    public func getMessages(owner: KeyPair, chatID: ChatID) async throws -> [ChatMessage] {
        try await withCheckedThrowingContinuation { c in
            chatMessagingService.getMessages(owner: owner, chatID: chatID, pagingToken: nil) { c.resume(with: $0) }
        }
    }

    @discardableResult
    public func sendMessage(owner: KeyPair, chatID: ChatID, text: String) async throws -> ChatMessage {
        try await withCheckedThrowingContinuation { c in
            chatMessagingService.sendMessage(owner: owner, chatID: chatID, text: text) { c.resume(with: $0) }
        }
    }

    public func markRead(owner: KeyPair, chatID: ChatID, messageID: MessageID) async throws {
        try await withCheckedThrowingContinuation { c in
            chatMessagingService.advancePointer(owner: owner, chatID: chatID, messageID: messageID) { c.resume(with: $0) }
        }
    }

    // MARK: - Event stream

    /// Start the single per-user event stream and return its decoded events.
    public nonisolated func openConversationStream(owner: KeyPair) -> AsyncStream<ChatStreamEvent> {
        Task { await eventStreamer.start(owner: owner) }
        return eventStreamer.events
    }

    public nonisolated func ensureConversationStreamConnected() {
        Task { await eventStreamer.ensureConnected() }
    }

    public nonisolated func closeConversationStream() {
        Task { await eventStreamer.stop() }
    }
}
