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
    private var _sendResult: ConversationMessage?
    private var _sent: [Sent] = []
    private var _markedRead: [MessageID] = []
    private var _didEnsure = false
    private var _didClose = false
    private var _streamContinuation: AsyncStream<ConversationStreamEvent>.Continuation?

    var feed: [Conversation] {
        get { lock.withLock { _feed } }
        set { lock.withLock { _feed = newValue } }
    }
    var messages: [ConversationMessage] {
        get { lock.withLock { _messages } }
        set { lock.withLock { _messages = newValue } }
    }
    var sendResult: ConversationMessage? {
        get { lock.withLock { _sendResult } }
        set { lock.withLock { _sendResult = newValue } }
    }
    var sent: [Sent] { lock.withLock { _sent } }
    var markedRead: [MessageID] { lock.withLock { _markedRead } }
    var didEnsure: Bool { lock.withLock { _didEnsure } }
    var didClose: Bool { lock.withLock { _didClose } }

    /// Push a live event onto the stream returned by `openConversationStream`.
    func emit(_ event: ConversationStreamEvent) {
        lock.withLock { _streamContinuation }?.yield(event)
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

    func getMessages(owner: KeyPair, conversationID: ConversationID) async throws -> [ConversationMessage] { messages }

    func sendMessage(owner: KeyPair, conversationID: ConversationID, text: String) async throws -> ConversationMessage {
        lock.withLock { _sent.append(Sent(conversationID: conversationID, text: text)) }
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
