//
//  MockConversations.swift
//  FlipcashTests
//

import Foundation
import FlipcashCore
@testable import Flipcash

/// Scriptable conformer for the four conversation capability protocols. Records
/// every call; the test sets scripted responses before driving the controller.
final class MockConversations: ConversationFetching, ConversationMessaging, ConversationEventStreaming, ProfileFetching, @unchecked Sendable {

    struct Sent: Sendable { let chatID: ChatID; let text: String }

    private let lock = NSLock()

    private var _feed: [Conversation] = []
    private var _messages: [ChatMessage] = []
    private var _profiles: [UserID: Profile] = [:]
    private var _sendResult: ChatMessage?
    private var _sent: [Sent] = []
    private var _markedRead: [MessageID] = []
    private var _didEnsure = false
    private var _didClose = false
    private var _streamContinuation: AsyncStream<ChatStreamEvent>.Continuation?

    var feed: [Conversation] {
        get { lock.withLock { _feed } }
        set { lock.withLock { _feed = newValue } }
    }
    var messages: [ChatMessage] {
        get { lock.withLock { _messages } }
        set { lock.withLock { _messages = newValue } }
    }
    var sendResult: ChatMessage? {
        get { lock.withLock { _sendResult } }
        set { lock.withLock { _sendResult = newValue } }
    }
    var sent: [Sent] { lock.withLock { _sent } }
    var markedRead: [MessageID] { lock.withLock { _markedRead } }
    var didEnsure: Bool { lock.withLock { _didEnsure } }
    var didClose: Bool { lock.withLock { _didClose } }

    func setProfile(_ profile: Profile, for userID: UserID) {
        lock.withLock { _profiles[userID] = profile }
    }

    /// Push a live event onto the stream returned by `openConversationStream`.
    func emit(_ event: ChatStreamEvent) {
        lock.withLock { _streamContinuation }?.yield(event)
    }

    // MARK: - ConversationFetching

    func getDmChatFeed(owner: KeyPair) async throws -> [Conversation] { feed }

    func getChat(owner: KeyPair, chatID: ChatID) async throws -> Conversation {
        guard let conversation = feed.first(where: { $0.id == chatID }) else {
            throw CancellationError()
        }
        return conversation
    }

    // MARK: - ConversationMessaging

    func getMessages(owner: KeyPair, chatID: ChatID) async throws -> [ChatMessage] { messages }

    func sendMessage(owner: KeyPair, chatID: ChatID, text: String) async throws -> ChatMessage {
        lock.withLock { _sent.append(Sent(chatID: chatID, text: text)) }
        return sendResult ?? ChatMessage(
            id: MessageID(value: 1), senderID: nil, text: text,
            date: Date(timeIntervalSince1970: 0), unreadSeq: 0
        )
    }

    func markRead(owner: KeyPair, chatID: ChatID, messageID: MessageID) async throws {
        lock.withLock { _markedRead.append(messageID) }
    }

    // MARK: - ConversationEventStreaming

    func openConversationStream(owner: KeyPair) -> AsyncStream<ChatStreamEvent> {
        let (stream, continuation) = AsyncStream<ChatStreamEvent>.makeStream()
        lock.withLock { _streamContinuation = continuation }
        return stream
    }

    func ensureConversationStreamConnected() { lock.withLock { _didEnsure = true } }
    func closeConversationStream() { lock.withLock { _didClose = true } }

    // MARK: - ProfileFetching

    func fetchProfile(userID: UserID, owner: KeyPair) async throws -> Profile {
        lock.withLock { _profiles[userID] } ?? .empty
    }
}
