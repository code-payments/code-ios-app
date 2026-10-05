//
//  EncryptedChatClient.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import os
import FlipcashCore

/// The chat surface `ConversationController` talks to, with DM end-to-end encryption applied at
/// the edge: every message read from the server comes back decrypted (or marked with why it
/// couldn't be), and every text sent into an encrypting chat goes out sealed.
///
/// The controller never sees ciphertext it could decrypt, so the store, the database and the UI
/// work on plaintext. A message whose peer key can't be fetched yet passes through undecrypted
/// and unmarked; the transcript hides it until a later read decrypts it.
final class EncryptedChatClient: Sendable {

    private let client: FlipClient
    private let keyring: ChatKeyring

    /// Every chat seen on its way through, so a message can be opened without a `GetChat`.
    private let conversations = OSAllocatedUnfairLock<[ConversationID: Conversation]>(initialState: [:])

    init(client: FlipClient, keyring: ChatKeyring) {
        self.client = client
        self.keyring = keyring
    }

    private func remember(_ conversation: Conversation) {
        conversations.withLock { $0[conversation.id] = conversation }
    }

    /// The chat `conversationID` names, fetched when it hasn't passed through yet.
    private func conversation(_ conversationID: ConversationID, owner: KeyPair) async throws -> Conversation {
        if let known = conversations.withLock({ $0[conversationID] }) { return known }
        let fetched = try await client.getChat(owner: owner, conversationID: conversationID)
        remember(fetched)
        return fetched
    }

    /// How `conversationID`'s messages open; waits on the key when the chat can't be fetched.
    private func opener(_ conversationID: ConversationID, owner: KeyPair) async -> ChatOpener {
        guard let conversation = try? await conversation(conversationID, owner: owner) else { return .awaitingKey }
        return await keyring.opener(for: conversation)
    }

    /// `conversation` remembered, with its preview message opened.
    private func opened(_ conversation: Conversation) async -> Conversation {
        remember(conversation)
        guard let lastMessage = conversation.lastMessage, lastMessage.isAwaitingDecryption else { return conversation }
        var conversation = conversation
        conversation.lastMessage = await keyring.open(lastMessage, in: conversation)
        return conversation
    }

    /// The seal for a send into `conversationID`, nil when it goes out in plaintext.
    private func sealForSending(_ conversationID: ConversationID, owner: KeyPair) async throws -> ChatSeal? {
        try await keyring.sealForSending(in: conversation(conversationID, owner: owner))
    }

    /// Runs a send, forgetting `conversationID` when the server refuses its encryption choice so a
    /// retry decides again from a fresh copy of the chat.
    private func refetchingOnRefusal<T>(_ conversationID: ConversationID, _ send: () async throws -> T) async throws -> T {
        do {
            return try await send()
        } catch ErrorSendMessage.encryptionNotAllowed {
            conversations.withLock { _ = $0.removeValue(forKey: conversationID) }
            throw ErrorSendMessage.encryptionNotAllowed
        } catch ErrorSendMessage.encryptionRequired {
            conversations.withLock { _ = $0.removeValue(forKey: conversationID) }
            throw ErrorSendMessage.encryptionRequired
        } catch ErrorEditMessage.encryptionNotAllowed {
            conversations.withLock { _ = $0.removeValue(forKey: conversationID) }
            throw ErrorEditMessage.encryptionNotAllowed
        } catch ErrorEditMessage.encryptionRequired {
            conversations.withLock { _ = $0.removeValue(forKey: conversationID) }
            throw ErrorEditMessage.encryptionRequired
        }
    }
}

// MARK: - ConversationFetching -

extension EncryptedChatClient: ConversationFetching {

    func getDmChatFeed(owner: KeyPair, type: ConversationType) async throws -> [Conversation] {
        var feed: [Conversation] = []
        for conversation in try await client.getDmChatFeed(owner: owner, type: type) {
            feed.append(await opened(conversation))
        }
        return feed
    }

    func getGroupChatFeed(owner: KeyPair) async throws -> [Conversation] {
        let feed = try await client.getGroupChatFeed(owner: owner)
        feed.forEach(remember)
        return feed
    }

    func getChat(owner: KeyPair, conversationID: ConversationID) async throws -> Conversation {
        await opened(try await client.getChat(owner: owner, conversationID: conversationID))
    }
}

// MARK: - ConversationMessaging -

extension EncryptedChatClient: ConversationMessaging {

    func getMessage(owner: KeyPair, conversationID: ConversationID, messageID: MessageID) async throws -> ConversationMessage? {
        guard let message = try await client.getMessage(owner: owner, conversationID: conversationID, messageID: messageID) else { return nil }
        guard message.isAwaitingDecryption else { return message }
        return await opener(conversationID, owner: owner).open(message)
    }

    func getMessages(owner: KeyPair, conversationID: ConversationID, before: MessageID?) async throws -> [ConversationMessage] {
        let messages = try await client.getMessages(owner: owner, conversationID: conversationID, before: before)
        guard messages.contains(where: \.isAwaitingDecryption) else { return messages }
        return await opener(conversationID, owner: owner).open(messages)
    }

    func getDelta(
        owner: KeyPair,
        conversationID: ConversationID,
        afterSequence: UInt64,
        onBatch: @MainActor @Sendable @escaping (_ messages: [ConversationMessage], _ checkpoint: UInt64?) -> Void
    ) async throws -> UInt64 {
        // Batches arrive on a synchronous callback, so the chat's keys are fetched before it starts.
        let opener = await opener(conversationID, owner: owner)
        return try await client.getDelta(owner: owner, conversationID: conversationID, afterSequence: afterSequence) { messages, checkpoint in
            onBatch(opener.open(messages), checkpoint)
        }
    }

    func sendMessage(owner: KeyPair, conversationID: ConversationID, text: String, repliedTo: MessageID?, clientMessageID: UUID) async throws -> ConversationMessage {
        try await refetchingOnRefusal(conversationID) {
            let seal = try await sealForSending(conversationID, owner: owner)
            return try await client.sendMessage(owner: owner, conversationID: conversationID, text: text, repliedTo: repliedTo, seal: seal, clientMessageID: clientMessageID)
        }
    }

    func editMessage(owner: KeyPair, conversationID: ConversationID, messageID: MessageID, text: String, repliedTo: MessageID?, expectedEventSequence: UInt64) async throws -> MessageMutation {
        try await refetchingOnRefusal(conversationID) {
            let seal = try await sealForSending(conversationID, owner: owner)
            return try await client.editMessage(owner: owner, conversationID: conversationID, messageID: messageID, text: text, repliedTo: repliedTo, seal: seal, expectedEventSequence: expectedEventSequence)
        }
    }

    func deleteMessage(owner: KeyPair, conversationID: ConversationID, messageID: MessageID, expectedEventSequence: UInt64) async throws -> MessageMutation {
        try await client.deleteMessage(owner: owner, conversationID: conversationID, messageID: messageID, expectedEventSequence: expectedEventSequence)
    }

    func addReaction(owner: KeyPair, conversationID: ConversationID, messageID: MessageID, emoji: String) async throws -> EmojiReaction {
        try await client.addReaction(owner: owner, conversationID: conversationID, messageID: messageID, emoji: emoji)
    }

    func removeReaction(owner: KeyPair, conversationID: ConversationID, messageID: MessageID, emoji: String) async throws -> EmojiReaction {
        try await client.removeReaction(owner: owner, conversationID: conversationID, messageID: messageID, emoji: emoji)
    }

    func getReactors(owner: KeyPair, conversationID: ConversationID, messageID: MessageID, emoji: String, pageSize: Int, pagingToken: Data?) async throws -> ReactorPage {
        try await client.getReactors(owner: owner, conversationID: conversationID, messageID: messageID, emoji: emoji, pageSize: pageSize, pagingToken: pagingToken)
    }

    func getReactionSummaries(owner: KeyPair, conversationID: ConversationID, messageIDs: [MessageID]) async throws -> [MessageID: ReactionState] {
        try await client.getReactionSummaries(owner: owner, conversationID: conversationID, messageIDs: messageIDs)
    }

    func markRead(owner: KeyPair, conversationID: ConversationID, messageID: MessageID) async throws {
        try await client.markRead(owner: owner, conversationID: conversationID, messageID: messageID)
    }

    func notifyIsTyping(owner: KeyPair, conversationID: ConversationID, state: TypingState) async throws {
        try await client.notifyIsTyping(owner: owner, conversationID: conversationID, state: state)
    }
}

// MARK: - ConversationEventStreaming -

extension EncryptedChatClient: ConversationEventStreaming {

    func subscribeConversationStream(owner: KeyPair) async -> (events: AsyncStream<ConversationStreamEvent>, connectionState: AsyncStream<EventStreamConnectionState>) {
        let (events, connectionState) = await client.subscribeConversationStream(owner: owner)
        let (opened, continuation) = AsyncStream.makeStream(of: ConversationStreamEvent.self)
        // One event at a time, so the stream's order survives a key fetch.
        let task = Task { [self] in
            for await event in events {
                continuation.yield(await open(event, owner: owner))
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
        return (opened, connectionState)
    }

    func ensureConversationStreamConnected() {
        client.ensureConversationStreamConnected()
    }

    func closeConversationStream() {
        client.closeConversationStream()
    }

    private func open(_ event: ConversationStreamEvent, owner: KeyPair) async -> ConversationStreamEvent {
        switch event {
        case .chatEvents(let conversationID, let events):
            guard events.contains(where: { $0.mutations.contains { $0.message.isAwaitingDecryption } }) else { return event }
            let opener = await opener(conversationID, owner: owner)
            return .chatEvents(conversationID: conversationID, events: events.map { chatEvent in
                DecodedChatEvent(
                    sequence: chatEvent.sequence,
                    count: chatEvent.count,
                    mutations: chatEvent.mutations.map { $0.opened(by: opener) }
                )
            })
        case .metadataRefresh(let conversation):
            return .metadataRefresh(await opened(conversation))
        case .lastActivityChanged, .readPointersChanged, .typingChanged, .rosterChanged,
             .viewerStateChanged, .titleChanged, .pictureChanged, .reactionsChanged, .lobbyChanged:
            return event
        }
    }
}

private extension DecodedMutation {
    func opened(by opener: ChatOpener) -> DecodedMutation {
        switch self {
        case .sent(let message):    .sent(opener.open(message))
        case .edited(let message):  .edited(opener.open(message))
        case .deleted(let message): .deleted(message)
        }
    }
}
