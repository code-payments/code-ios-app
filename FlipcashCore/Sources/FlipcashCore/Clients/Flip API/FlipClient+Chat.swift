//
//  FlipClient+Chat.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

extension FlipClient {

    /// Page the DM chat feed to exhaustion against a single pinned snapshot.
    /// The caller must already be consuming its `subscribeConversationStream` events so updates
    /// that land mid-pagination aren't lost.
    public func getDmChatFeed(owner: KeyPair, type: ConversationType) async throws -> [Conversation] {
        var all: [Conversation] = []
        var pagingToken: Data?

        while true {
            let page = try await withCheckedThrowingContinuation { c in
                chatService.getDmChatFeed(owner: owner, type: type, pagingToken: pagingToken) { c.resume(with: $0) }
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

    /// Streams the delta since `afterSequence` to `onBatch` (each with its resume checkpoint) and
    /// returns the chat's head on clean completion. Throws `ErrorGetDelta` on `.resetRequired`/denied/
    /// transport failure.
    public func getDelta(
        owner: KeyPair,
        conversationID: ConversationID,
        afterSequence: UInt64,
        onBatch: @MainActor @Sendable @escaping (_ messages: [ConversationMessage], _ checkpoint: UInt64?) -> Void
    ) async throws -> UInt64 {
        try await withCheckedThrowingContinuation { c in
            chatMessagingService.getDelta(owner: owner, conversationID: conversationID, afterSequence: afterSequence, onBatch: onBatch) { c.resume(with: $0) }
        }
    }

    @discardableResult
    public func sendMessage(owner: KeyPair, conversationID: ConversationID, text: String, clientMessageID: UUID) async throws -> ConversationMessage {
        try await withCheckedThrowingContinuation { c in
            chatMessagingService.sendMessage(owner: owner, conversationID: conversationID, text: text, clientMessageID: clientMessageID) { c.resume(with: $0) }
        }
    }

    public func editMessage(
        owner: KeyPair,
        conversationID: ConversationID,
        messageID: MessageID,
        text: String,
        expectedEventSequence: UInt64
    ) async throws -> MessageMutation {
        try await withCheckedThrowingContinuation { c in
            chatMessagingService.editMessage(
                owner: owner,
                conversationID: conversationID,
                messageID: messageID,
                text: text,
                expectedEventSequence: expectedEventSequence
            ) { c.resume(with: $0) }
        }
    }

    public func deleteMessage(
        owner: KeyPair,
        conversationID: ConversationID,
        messageID: MessageID,
        expectedEventSequence: UInt64
    ) async throws -> MessageMutation {
        try await withCheckedThrowingContinuation { c in
            chatMessagingService.deleteMessage(
                owner: owner,
                conversationID: conversationID,
                messageID: messageID,
                expectedEventSequence: expectedEventSequence
            ) { c.resume(with: $0) }
        }
    }

    public func markRead(owner: KeyPair, conversationID: ConversationID, messageID: MessageID) async throws {
        try await withCheckedThrowingContinuation { c in
            chatMessagingService.advancePointer(owner: owner, conversationID: conversationID, messageID: messageID) { c.resume(with: $0) }
        }
    }

    public func notifyIsTyping(owner: KeyPair, conversationID: ConversationID, state: TypingState) async throws {
        try await withCheckedThrowingContinuation { c in
            chatMessagingService.notifyIsTyping(owner: owner, conversationID: conversationID, state: state) { c.resume(with: $0) }
        }
    }

    // MARK: - Event stream

    /// Attach this session's consumer to the single per-user event stream, returning fresh decoded-event
    /// and connection-state streams and opening the stream for `owner`. Each session gets its own pair —
    /// see `EventStreamer.subscribe` for why reusing one across sessions strands a switched-to account.
    public nonisolated func subscribeConversationStream(owner: KeyPair) async -> (events: AsyncStream<ConversationStreamEvent>, connectionState: AsyncStream<EventStreamConnectionState>) {
        await eventStreamer.subscribe(owner: owner)
    }

    public nonisolated func ensureConversationStreamConnected() {
        Task { await eventStreamer.ensureConnected() }
    }

    public nonisolated func closeConversationStream() {
        Task { await eventStreamer.stop() }
    }
}
