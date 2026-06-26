//
//  MockConversations.swift
//  FlipcashTests
//

import Foundation
import FlipcashCore
@testable import Flipcash

/// Scriptable conformer for the four conversation capability protocols. Records
/// every call; the test sets scripted responses before driving the controller.
final class MockConversations: ConversationFetching, ConversationMessaging, ConversationEventStreaming, @unchecked Sendable {

    struct Sent: Sendable { let conversationID: ConversationID; let text: String }

    private let lock = NSLock()

    private var _feed: [Conversation] = []
    private var _messages: [ConversationMessage] = []
    private var _olderMessages: [ConversationMessage] = []
    private var _olderQueries: [MessageID] = []
    private var _latestPageQueries: [ConversationID] = []
    private var _sendResult: ConversationMessage?
    private var _sendError: Error?
    private var _sentClientIDs: [UUID] = []
    private var _sent: [Sent] = []
    private var _markedRead: [MessageID] = []
    private var _didEnsure = false
    private var _didClose = false
    private var _streamContinuation: AsyncStream<ConversationStreamEvent>.Continuation?
    private var _connectionStateContinuation: AsyncStream<EventStreamConnectionState>.Continuation?

    var feed: [Conversation] {
        get { lock.withLock { _feed } }
        set { lock.withLock { _feed = newValue } }
    }
    var messages: [ConversationMessage] {
        get { lock.withLock { _messages } }
        set { lock.withLock { _messages = newValue } }
    }
    /// Scripted older page returned when `getMessages` is called with `before != nil`.
    var olderMessages: [ConversationMessage] {
        get { lock.withLock { _olderMessages } }
        set { lock.withLock { _olderMessages = newValue } }
    }
    /// The `before` cursors `getMessages` was paged with.
    var olderQueries: [MessageID] { lock.withLock { _olderQueries } }
    /// The conversations `getMessages` was asked for the newest page of (`before == nil`).
    var latestPageQueries: [ConversationID] { lock.withLock { _latestPageQueries } }
    var sendResult: ConversationMessage? {
        get { lock.withLock { _sendResult } }
        set { lock.withLock { _sendResult = newValue } }
    }
    /// When set, `sendMessage` throws this instead of returning a message.
    var sendError: Error? {
        get { lock.withLock { _sendError } }
        set { lock.withLock { _sendError = newValue } }
    }
    /// The client message ids `sendMessage` was called with, in order.
    var sentClientIDs: [UUID] { lock.withLock { _sentClientIDs } }
    var sent: [Sent] { lock.withLock { _sent } }
    var markedRead: [MessageID] { lock.withLock { _markedRead } }
    var didEnsure: Bool { lock.withLock { _didEnsure } }
    var didClose: Bool { lock.withLock { _didClose } }
    /// Whether `openConversationStream` has been called — events emitted
    /// before that are dropped, so tests wait on this before `emit(_:)`.
    var streamOpened: Bool { lock.withLock { _streamContinuation != nil } }
    /// Whether `conversationConnectionState` has been subscribed — states emitted
    /// before that are dropped, so tests wait on this before `emitConnectionState(_:)`.
    var connectionStateStreamOpened: Bool { lock.withLock { _connectionStateContinuation != nil } }

    /// Push a live event onto the stream returned by `openConversationStream`.
    func emit(_ event: ConversationStreamEvent) {
        lock.withLock { _streamContinuation }?.yield(event)
    }

    /// Push a connection-state transition onto the stream returned by
    /// `conversationConnectionState`, as the streamer does on a ping or teardown.
    func emitConnectionState(_ state: EventStreamConnectionState) {
        lock.withLock { _connectionStateContinuation }?.yield(state)
    }

    // MARK: - ConversationFetching

    func getDmChatFeed(owner: KeyPair) async throws -> [Conversation] { feed }

    func getChat(owner: KeyPair, conversationID: ConversationID) async throws -> Conversation {
        guard let conversation = feed.first(where: { $0.id == conversationID }) else {
            throw CancellationError()
        }
        return conversation
    }

    // MARK: - ConversationMessaging

    func getMessages(owner: KeyPair, conversationID: ConversationID, before: MessageID?) async throws -> [ConversationMessage] {
        guard let before else {
            lock.withLock { _latestPageQueries.append(conversationID) }
            return messages
        }
        lock.withLock { _olderQueries.append(before) }
        return olderMessages
    }

    func sendMessage(owner: KeyPair, conversationID: ConversationID, text: String, clientMessageID: UUID) async throws -> ConversationMessage {
        lock.withLock {
            _sent.append(Sent(conversationID: conversationID, text: text))
            _sentClientIDs.append(clientMessageID)
        }
        if let error = sendError { throw error }
        return sendResult ?? ConversationMessage(
            id: MessageID(value: 1), senderID: nil, content: .text(text),
            date: Date(timeIntervalSince1970: 0), unreadSeq: 0
        )
    }

    func markRead(owner: KeyPair, conversationID: ConversationID, messageID: MessageID) async throws {
        lock.withLock { _markedRead.append(messageID) }
    }

    // MARK: - ConversationEventStreaming

    func openConversationStream(owner: KeyPair) -> AsyncStream<ConversationStreamEvent> {
        let (stream, continuation) = AsyncStream<ConversationStreamEvent>.makeStream()
        lock.withLock { _streamContinuation = continuation }
        return stream
    }

    func conversationConnectionState() -> AsyncStream<EventStreamConnectionState> {
        let (stream, continuation) = AsyncStream<EventStreamConnectionState>.makeStream()
        lock.withLock { _connectionStateContinuation = continuation }
        return stream
    }

    func ensureConversationStreamConnected() { lock.withLock { _didEnsure = true } }
    func closeConversationStream() { lock.withLock { _didClose = true } }
}

@MainActor
final class MockDMContactNaming: DMContactNaming {

    var names: [ConversationID: String] = [:]

    func contactDisplayName(forDMChat conversationID: ConversationID) -> String? {
        names[conversationID]
    }
}
