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

    /// Page the group chat feed to exhaustion against a single pinned snapshot. Unlike a DM feed, the
    /// caller's own membership can change mid-read (a join or a leave lands as a `rosterChanged`
    /// stream event, not a feed mutation) — the same live-stream caveat as `getDmChatFeed` applies.
    public func getGroupChatFeed(owner: KeyPair) async throws -> [Conversation] {
        var all: [Conversation] = []
        var pagingToken: Data?

        while true {
            let page = try await withCheckedThrowingContinuation { c in
                chatService.getGroupChatFeed(owner: owner, pagingToken: pagingToken) { c.resume(with: $0) }
            }
            all.append(contentsOf: page.conversations)
            if !page.hasMore { break }
            pagingToken = page.pagingToken
        }

        return all
    }

    /// Starts a new group chat and returns its metadata on success. `rules` gates who may read/join
    /// and who may send; `nil` leaves the chat unrestricted.
    ///
    /// `idempotencyKey` must be minted by the caller where the user's intent to create the chat
    /// originates (not here) and reused for every retry of that same attempt — see
    /// `ChatService.startChat`. A retry with the same key returns the original chat.
    public func startChat(owner: KeyPair, title: String, pictureBlobID: BlobID?, rules: ConversationRules?, idempotencyKey: UUID) async throws -> Conversation {
        try await withCheckedThrowingContinuation { c in
            chatService.startChat(owner: owner, title: title, pictureBlobID: pictureBlobID, rules: rules, idempotencyKey: idempotencyKey) { c.resume(with: $0) }
        }
    }

    /// Joins an existing group chat. Fails with `.rulesNotSatisfied` when the caller doesn't meet the
    /// chat's `ConversationRules`.
    public func joinChat(owner: KeyPair, conversationID: ConversationID) async throws -> Conversation {
        try await withCheckedThrowingContinuation { c in
            chatService.joinChat(owner: owner, conversationID: conversationID) { c.resume(with: $0) }
        }
    }

    /// Leaves a group chat. The caller's own `rosterChanged` event (naming itself) is what actually
    /// drops the chat from the local feed and database — this call just tells the server to emit it.
    public func leaveChat(owner: KeyPair, conversationID: ConversationID) async throws {
        try await withCheckedThrowingContinuation { c in
            chatService.leaveChat(owner: owner, conversationID: conversationID) { c.resume(with: $0) }
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
    public func sendMessage(owner: KeyPair, conversationID: ConversationID, text: String, repliedTo: MessageID?, clientMessageID: UUID) async throws -> ConversationMessage {
        try await withCheckedThrowingContinuation { c in
            chatMessagingService.sendMessage(owner: owner, conversationID: conversationID, text: text, repliedTo: repliedTo, clientMessageID: clientMessageID) { c.resume(with: $0) }
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
