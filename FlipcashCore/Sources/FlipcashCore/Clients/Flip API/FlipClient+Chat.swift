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
            all.append(contentsOf: page.conversations)
            if !page.hasMore { break }
            pagingToken = page.pagingToken
        }

        return all
    }

    public func getChat(owner: KeyPair, conversationID: ConversationID) async throws -> Conversation {
        try await withCheckedThrowingContinuation { c in
            chatService.getChat(owner: owner, conversationID: conversationID) { c.resume(with: $0) }
        }
    }

    public func getMessages(owner: KeyPair, conversationID: ConversationID, before: MessageID?) async throws -> [ConversationMessage] {
        try await withCheckedThrowingContinuation { c in
            chatMessagingService.getMessages(owner: owner, conversationID: conversationID, pagingToken: before?.pagingToken) { c.resume(with: $0) }
        }
    }

    @discardableResult
    public func sendMessage(owner: KeyPair, conversationID: ConversationID, text: String) async throws -> ConversationMessage {
        try await withCheckedThrowingContinuation { c in
            chatMessagingService.sendMessage(owner: owner, conversationID: conversationID, text: text) { c.resume(with: $0) }
        }
    }

    public func markRead(owner: KeyPair, conversationID: ConversationID, messageID: MessageID) async throws {
        try await withCheckedThrowingContinuation { c in
            chatMessagingService.advancePointer(owner: owner, conversationID: conversationID, messageID: messageID) { c.resume(with: $0) }
        }
    }

    // MARK: - Event stream

    /// Start the single per-user event stream and return its decoded events.
    public nonisolated func openConversationStream(owner: KeyPair) -> AsyncStream<ConversationStreamEvent> {
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
