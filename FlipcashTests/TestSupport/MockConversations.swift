//
//  MockConversations.swift
//  FlipcashTests
//

import Foundation
import FlipcashCore
@testable import Flipcash

/// Scriptable conformer for the conversation capability protocols. Records
/// every call; the test sets scripted responses before driving the controller.
final class MockConversations: ConversationFetching, ConversationMembership, ConversationViewerSettings, ConversationMessaging, ConversationEventStreaming, @unchecked Sendable {

    struct Sent: Sendable {
        let conversationID: ConversationID
        let text: String
        let repliedTo: MessageID?
    }
    struct TypingCall: Sendable { let conversationID: ConversationID; let state: TypingState }
    /// A scripted `GetDelta` batch: one `onBatch` call with these messages + checkpoint.
    struct DeltaBatch: Sendable { let messages: [ConversationMessage]; let checkpoint: UInt64? }

    struct Edited: Sendable, Equatable {
        let conversationID: ConversationID
        let messageID: MessageID
        let text: String
        let expectedEventSequence: UInt64
    }

    struct Deleted: Sendable, Equatable {
        let conversationID: ConversationID
        let messageID: MessageID
        let expectedEventSequence: UInt64
    }

    private let lock = NSLock()

    private var _feed: [Conversation] = []
    private var _groupFeed: [Conversation] = []
    private var _joined: [ConversationID] = []
    private var _left: [ConversationID] = []
    private var _joinError: Error?
    private var _leaveError: Error?
    private var _muted: [(conversationID: ConversationID, mute: ConversationMuteState)] = []
    private var _unmuted: [ConversationID] = []
    private var _viewerStateResult: ConversationViewerState?
    private var _muteError: Error?
    private var _messages: [ConversationMessage] = []
    private var _olderMessages: [ConversationMessage] = []
    private var _olderQueries: [MessageID] = []
    private var _latestPageQueries: [ConversationID] = []
    private var _sendResult: ConversationMessage?
    private var _sendError: Error?
    private var _sentClientIDs: [UUID] = []
    private var _sent: [Sent] = []
    private var _edited: [Edited] = []
    private var _deleted: [Deleted] = []
    private var _editResult: MessageMutation?
    private var _editError: (any Error)?
    private var _deleteResult: MessageMutation?
    private var _deleteError: (any Error)?
    private var _markedRead: [MessageID] = []
    private var _typingCalls: [TypingCall] = []
    private var _typingCallsBegun = 0
    private var _heldTypingStates: Set<TypingState> = []
    private var _typingGateWaiters: [TypingState: [CheckedContinuation<Void, Never>]] = [:]
    private var _deltaBatches: [DeltaBatch] = []
    private var _deltaHead: UInt64 = 0
    private var _deltaError: Error?
    private var _deltaAfterSequences: [UInt64] = []
    private var _didEnsure = false
    private var _didClose = false
    private var _streamContinuation: AsyncStream<ConversationStreamEvent>.Continuation?
    private var _connectionStateContinuation: AsyncStream<EventStreamConnectionState>.Continuation?

    var feed: [Conversation] {
        get { lock.withLock { _feed } }
        set { lock.withLock { _feed = newValue } }
    }
    /// Scripted `GetGroupChatFeed` result — the groups the caller has joined.
    var groupFeed: [Conversation] {
        get { lock.withLock { _groupFeed } }
        set { lock.withLock { _groupFeed = newValue } }
    }
    /// Conversations `joinChat` was called for, in order.
    var joined: [ConversationID] { lock.withLock { _joined } }
    /// Conversations `leaveChat` was called for, in order.
    var left: [ConversationID] { lock.withLock { _left } }
    var joinError: Error? {
        get { lock.withLock { _joinError } }
        set { lock.withLock { _joinError = newValue } }
    }
    var leaveError: Error? {
        get { lock.withLock { _leaveError } }
        set { lock.withLock { _leaveError = newValue } }
    }

    /// Every `MuteChat` call, in order, with the duration each asked for.
    var muted: [(conversationID: ConversationID, mute: ConversationMuteState)] { lock.withLock { _muted } }
    var unmuted: [ConversationID] { lock.withLock { _unmuted } }
    /// Viewer state both mute RPCs return. Unset returns one at version 1 carrying the requested
    /// mute, which is enough for any test that isn't exercising version comparison.
    var viewerStateResult: ConversationViewerState? {
        get { lock.withLock { _viewerStateResult } }
        set { lock.withLock { _viewerStateResult = newValue } }
    }
    var muteError: Error? {
        get { lock.withLock { _muteError } }
        set { lock.withLock { _muteError = newValue } }
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
    /// Forget the recorded newest-page fetches, so a test can assert on the ones its own exercise
    /// makes rather than the post-feed backfill that already ran during `start()`.
    func clearLatestPageQueries() { lock.withLock { _latestPageQueries.removeAll() } }
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
    /// The edits `editMessage` was called with, in order.
    var edited: [Edited] { lock.withLock { _edited } }
    /// The deletes `deleteMessage` was called with, in order.
    var deleted: [Deleted] { lock.withLock { _deleted } }
    var editResult: MessageMutation? {
        get { lock.withLock { _editResult } }
        set { lock.withLock { _editResult = newValue } }
    }
    /// When set, `editMessage` throws this instead of returning a mutation.
    var editError: (any Error)? {
        get { lock.withLock { _editError } }
        set { lock.withLock { _editError = newValue } }
    }
    var deleteResult: MessageMutation? {
        get { lock.withLock { _deleteResult } }
        set { lock.withLock { _deleteResult = newValue } }
    }
    /// When set, `deleteMessage` throws this instead of returning a mutation.
    var deleteError: (any Error)? {
        get { lock.withLock { _deleteError } }
        set { lock.withLock { _deleteError = newValue } }
    }
    var markedRead: [MessageID] { lock.withLock { _markedRead } }
    var typingCalls: [TypingCall] { lock.withLock { _typingCalls } }
    /// Number of `notifyIsTyping` calls entered, counted before the gate — the
    /// awaitable signal that a send is in flight.
    var typingCallsBegun: Int { lock.withLock { _typingCallsBegun } }
    /// Parks every `notifyIsTyping` for `state` inside the transport until
    /// `releaseTyping(_:)`, so a test can queue further sends while the first is
    /// provably still in flight. Opt-in: ungated states are unaffected.
    func holdTyping(_ state: TypingState) {
        lock.withLock { _ = _heldTypingStates.insert(state) }
    }

    /// Opens the gate for `state` and leaves it open, so later sends of that state
    /// pass straight through.
    func releaseTyping(_ state: TypingState) {
        let waiters = lock.withLock {
            _heldTypingStates.remove(state)
            return _typingGateWaiters.removeValue(forKey: state) ?? []
        }
        for waiter in waiters { waiter.resume() }
    }

    private func awaitTypingGate(for state: TypingState) async {
        await withCheckedContinuation { continuation in
            let parked = lock.withLock { () -> Bool in
                guard _heldTypingStates.contains(state) else { return false }
                _typingGateWaiters[state, default: []].append(continuation)
                return true
            }
            if !parked { continuation.resume() }
        }
    }
    /// Batches `getDelta` delivers to `onBatch`, in order.
    var deltaBatches: [DeltaBatch] {
        get { lock.withLock { _deltaBatches } }
        set { lock.withLock { _deltaBatches = newValue } }
    }
    /// The head sequence `getDelta` returns on clean completion.
    var deltaHead: UInt64 {
        get { lock.withLock { _deltaHead } }
        set { lock.withLock { _deltaHead = newValue } }
    }
    /// When set, `getDelta` throws this after delivering any scripted batches (e.g. `.resetRequired`).
    var deltaError: Error? {
        get { lock.withLock { _deltaError } }
        set { lock.withLock { _deltaError = newValue } }
    }
    /// The `afterSequence` cursors `getDelta` was called with, in order.
    var deltaAfterSequences: [UInt64] { lock.withLock { _deltaAfterSequences } }
    var didEnsure: Bool { lock.withLock { _didEnsure } }
    var didClose: Bool { lock.withLock { _didClose } }
    /// Whether `subscribeConversationStream` has been called — events emitted
    /// before that are dropped, so tests wait on this before `emit(_:)`.
    var streamOpened: Bool { lock.withLock { _streamContinuation != nil } }
    /// Whether `subscribeConversationStream` has vended a connection-state stream — states emitted
    /// before that are dropped, so tests wait on this before `emitConnectionState(_:)`.
    var connectionStateStreamOpened: Bool { lock.withLock { _connectionStateContinuation != nil } }

    /// Push a live event onto the stream returned by `subscribeConversationStream`.
    func emit(_ event: ConversationStreamEvent) {
        lock.withLock { _streamContinuation }?.yield(event)
    }

    /// Push a connection-state transition onto the stream returned by
    /// `subscribeConversationStream`, as the streamer does on a ping or teardown.
    func emitConnectionState(_ state: EventStreamConnectionState) {
        lock.withLock { _connectionStateContinuation }?.yield(state)
    }

    // MARK: - ConversationFetching

    func getDmChatFeed(owner: KeyPair, type: ConversationType) async throws -> [Conversation] { feed }

    func getGroupChatFeed(owner: KeyPair) async throws -> [Conversation] { groupFeed }

    func getChat(owner: KeyPair, conversationID: ConversationID) async throws -> Conversation {
        guard let conversation = feed.first(where: { $0.id == conversationID }) else {
            throw CancellationError()
        }
        return conversation
    }

    // MARK: - ConversationMembership

    /// Answers with the chat as the group feed or the DM feed holds it; a join for a chat neither
    /// knows has nothing to return, which is what the real RPC's `NOT_FOUND` becomes here.
    func joinChat(owner: KeyPair, conversationID: ConversationID) async throws -> Conversation {
        lock.withLock { _joined.append(conversationID) }
        if let joinError { throw joinError }
        guard let conversation = (groupFeed + feed).first(where: { $0.id == conversationID }) else {
            throw ErrorJoinChat.notFound
        }
        return conversation
    }

    func leaveChat(owner: KeyPair, conversationID: ConversationID) async throws {
        lock.withLock { _left.append(conversationID) }
        if let leaveError { throw leaveError }
    }

    // MARK: - ConversationViewerSettings

    func muteChat(owner: KeyPair, conversationID: ConversationID, mute: ConversationMuteState) async throws -> ConversationViewerState {
        lock.withLock { _muted.append((conversationID, mute)) }
        if let muteError { throw muteError }
        return viewerStateResult ?? ConversationViewerState(mute: mute, version: 1)
    }

    func unmuteChat(owner: KeyPair, conversationID: ConversationID) async throws -> ConversationViewerState {
        lock.withLock { _unmuted.append(conversationID) }
        if let muteError { throw muteError }
        return viewerStateResult ?? ConversationViewerState(mute: nil, version: 1)
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

    func sendMessage(owner: KeyPair, conversationID: ConversationID, text: String, repliedTo: MessageID?, clientMessageID: UUID) async throws -> ConversationMessage {
        lock.withLock {
            _sent.append(Sent(conversationID: conversationID, text: text, repliedTo: repliedTo))
            _sentClientIDs.append(clientMessageID)
        }
        if let error = sendError { throw error }
        return sendResult ?? ConversationMessage(
            id: MessageID(value: 1), senderID: nil, content: .text(text),
            date: Date(timeIntervalSince1970: 0), unreadSeq: 0, repliedTo: repliedTo
        )
    }

    func editMessage(owner: KeyPair, conversationID: ConversationID, messageID: MessageID, text: String, expectedEventSequence: UInt64) async throws -> MessageMutation {
        lock.withLock {
            _edited.append(Edited(conversationID: conversationID, messageID: messageID, text: text, expectedEventSequence: expectedEventSequence))
        }
        if let editError { throw editError }
        guard let editResult else { throw ErrorEditMessage.unknown }
        return editResult
    }

    func deleteMessage(owner: KeyPair, conversationID: ConversationID, messageID: MessageID, expectedEventSequence: UInt64) async throws -> MessageMutation {
        lock.withLock {
            _deleted.append(Deleted(conversationID: conversationID, messageID: messageID, expectedEventSequence: expectedEventSequence))
        }
        if let deleteError { throw deleteError }
        guard let deleteResult else { throw ErrorDeleteMessage.unknown }
        return deleteResult
    }

    func getDelta(
        owner: KeyPair,
        conversationID: ConversationID,
        afterSequence: UInt64,
        onBatch: @MainActor @Sendable @escaping (_ messages: [ConversationMessage], _ checkpoint: UInt64?) -> Void
    ) async throws -> UInt64 {
        lock.withLock { _deltaAfterSequences.append(afterSequence) }
        let (batches, head, error) = lock.withLock { (_deltaBatches, _deltaHead, _deltaError) }
        for batch in batches {
            await MainActor.run { onBatch(batch.messages, batch.checkpoint) }
        }
        if let error { throw error }
        return head
    }

    func markRead(owner: KeyPair, conversationID: ConversationID, messageID: MessageID) async throws {
        lock.withLock { _markedRead.append(messageID) }
    }

    func notifyIsTyping(owner: KeyPair, conversationID: ConversationID, state: TypingState) async throws {
        lock.withLock { _typingCallsBegun += 1 }
        await awaitTypingGate(for: state)
        lock.withLock { _typingCalls.append(TypingCall(conversationID: conversationID, state: state)) }
    }

    // MARK: - ConversationEventStreaming

    func subscribeConversationStream(owner: KeyPair) async -> (events: AsyncStream<ConversationStreamEvent>, connectionState: AsyncStream<EventStreamConnectionState>) {
        let (events, eventContinuation) = AsyncStream<ConversationStreamEvent>.makeStream()
        let (state, stateContinuation) = AsyncStream<EventStreamConnectionState>.makeStream()
        lock.withLock {
            _streamContinuation = eventContinuation
            _connectionStateContinuation = stateContinuation
        }
        return (events, state)
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
