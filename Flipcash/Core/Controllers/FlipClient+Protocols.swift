//
//  FlipClient+Protocols.swift
//  Flipcash
//
//  Lives in the app target so async protocol methods inherit the
//  `NonisolatedNonsendingByDefault` upcoming feature — calls preserve
//  caller isolation and don't force sending `any ContactVerifying`
//  across actor boundaries.
//

import Foundation
import FlipcashCore

/// Phone and email verification surface used by `VerificationViewModel`.
/// Each method maps 1:1 to a Flipcash backend RPC; the viewmodel drives the
/// state machine and the conformer issues the calls.
protocol ContactVerifying: AnyObject {

    func sendVerificationCode(phone: String, owner: KeyPair) async throws
    func checkVerificationCode(phone: String, code: String, owner: KeyPair) async throws

    func sendEmailVerification(email: String, owner: KeyPair) async throws
    func checkEmailCode(email: String, code: String, owner: KeyPair) async throws
}

/// Coinbase CDP JWT minting surface used by the session-scoped Coinbase
/// service. JWTs are URI-bound so each request needs one signed for that
/// exact method/path or Coinbase rejects with 401.
protocol OnrampAuthorizing: AnyObject {

    func fetchCoinbaseOnrampJWT(
        apiKey: String,
        owner: KeyPair,
        method: String,
        path: String
    ) async throws -> String
}

/// Contact-sync RPC surface used by `ContactSyncController`. Each method maps
/// 1:1 to a `flipcash.contact.v1.ContactList` server RPC (plus the matched-set
/// stream); the controller drives the state machine and the conformer issues
/// the calls. `Sendable` so the controller can hold `any ContactSyncing` as a
/// `nonisolated let` and call it from off-main `@concurrent` work.
protocol ContactSyncing: AnyObject, Sendable {

    func checkContactSync(checksum: Data, owner: KeyPair) async throws -> CheckSyncResult

    func uploadContactDelta(
        adds: [String],
        removes: [String],
        oldChecksum: Data,
        newChecksum: Data,
        owner: KeyPair
    ) async throws -> DeltaUploadResult

    func uploadAllContacts(phones: [String], checksum: Data, owner: KeyPair) async throws

    func streamFlipcashContacts(checksum: Data, owner: KeyPair) -> AsyncThrowingStream<MatchedContact, Error>
}

/// Conversation read surface used by `ConversationController` — the DM and group feeds plus a
/// single conversation by id. Maps 1:1 to the `flipcash.chat.v1.Chat` RPCs.
protocol ConversationFetching: AnyObject, Sendable {
    func getDmChatFeed(owner: KeyPair, type: ConversationType) async throws -> [Conversation]
    /// The groups the caller is a member of. A group reached by link and not joined is not in it.
    func getGroupChatFeed(owner: KeyPair) async throws -> [Conversation]
    func getChat(owner: KeyPair, conversationID: ConversationID) async throws -> Conversation
}

/// Group membership surface used by `ConversationController`. Separate from ``ConversationFetching``
/// because these write: they are the only chat RPCs that change what the caller is a member of.
protocol ConversationMembership: AnyObject, Sendable {
    /// Joins a chat, returning its metadata as it stands after the join.
    func joinChat(owner: KeyPair, conversationID: ConversationID) async throws -> Conversation
    func leaveChat(owner: KeyPair, conversationID: ConversationID) async throws
}

/// Per-viewer chat settings used by `ConversationController` — currently only mute. Separate from
/// ``ConversationMembership`` because nothing here changes who is in the chat: mute is the viewer's
/// own state, and the server keeps it per-viewer.
protocol ConversationViewerSettings: AnyObject, Sendable {
    /// Mutes a chat until `mute` lapses, or forever. Returns the resulting viewer state, version
    /// included, so the caller can seat it under the same greater-value-wins rule the stream uses.
    func muteChat(owner: KeyPair, conversationID: ConversationID, mute: ConversationMuteState) async throws -> ConversationViewerState
    /// Unmutes a chat. Its own RPC rather than a zero-length mute — the contract has no such shape.
    func unmuteChat(owner: KeyPair, conversationID: ConversationID) async throws -> ConversationViewerState
}

/// DM message send/read surface used by `ConversationController`. Maps to the
/// `flipcash.messaging.v1.Messaging` RPCs.
protocol ConversationMessaging: AnyObject, Sendable {
    /// Fetches one message by id, or nil when the chat has no such message.
    func getMessage(owner: KeyPair, conversationID: ConversationID, messageID: MessageID) async throws -> ConversationMessage?
    /// Fetches a page of messages. `before == nil` returns the newest page;
    /// pass the oldest currently-loaded id to page strictly older (history).
    func getMessages(owner: KeyPair, conversationID: ConversationID, before: MessageID?) async throws -> [ConversationMessage]
    /// Reconnect/cold-boot catch-up. Streams the messages changed since `afterSequence` to `onBatch`
    /// (each with its resume checkpoint), returning the chat's head sequence on clean completion.
    /// Throws `ErrorGetDelta.resetRequired` when the cursor is too far behind (caller re-syncs via
    /// `getMessages`).
    func getDelta(
        owner: KeyPair,
        conversationID: ConversationID,
        afterSequence: UInt64,
        onBatch: @MainActor @Sendable @escaping (_ messages: [ConversationMessage], _ checkpoint: UInt64?) -> Void
    ) async throws -> UInt64
    func sendMessage(owner: KeyPair, conversationID: ConversationID, text: String, repliedTo: MessageID?, clientMessageID: UUID) async throws -> ConversationMessage
    /// Replaces a message's text. `expectedEventSequence` is the optimistic-concurrency guard: the
    /// server applies the edit only if the message still carries that sequence, and reports a
    /// conflict with the winning state otherwise.
    func editMessage(owner: KeyPair, conversationID: ConversationID, messageID: MessageID, text: String, expectedEventSequence: UInt64) async throws -> MessageMutation
    /// Tombstones a message, guarded by `expectedEventSequence` the same way as `editMessage`.
    func deleteMessage(owner: KeyPair, conversationID: ConversationID, messageID: MessageID, expectedEventSequence: UInt64) async throws -> MessageMutation
    func markRead(owner: KeyPair, conversationID: ConversationID, messageID: MessageID) async throws
    func notifyIsTyping(owner: KeyPair, conversationID: ConversationID, state: TypingState) async throws
}

/// The single per-user event stream surface used by `ConversationController`. Wraps the
/// `event.v1 StreamEvents` lifecycle behind `ConversationStreamEvent`.
protocol ConversationEventStreaming: AnyObject, Sendable {
    /// Attach this session's consumer to the single per-user event stream, returning fresh decoded-event
    /// and connection-state streams. Each session gets its own pair, so a switched-to account isn't
    /// stranded on a dead stream. The event stream carries no cursor, so the controller treats the first
    /// `.live` as the initial connection and, on each `.live` after (a reconnect), reconciles the missed
    /// window from the event-log cursor via `GetDelta`.
    func subscribeConversationStream(owner: KeyPair) async -> (events: AsyncStream<ConversationStreamEvent>, connectionState: AsyncStream<EventStreamConnectionState>)
    func ensureConversationStreamConnected()
    func closeConversationStream()
}

/// The chat reads that `FlipClient` exposes with a defaulted `viewMode`, restated without it.
///
/// A default argument doesn't witness a protocol requirement that omits the parameter, so these
/// forward at `.full` — the only mode this app reads in. A screen that needs a redacted read belongs
/// on the protocol above, not here.
extension FlipClient {

    func getChat(owner: KeyPair, conversationID: ConversationID) async throws -> Conversation {
        try await getChat(owner: owner, conversationID: conversationID, viewMode: .full)
    }

    func getMessage(owner: KeyPair, conversationID: ConversationID, messageID: MessageID) async throws -> ConversationMessage? {
        try await getMessage(owner: owner, conversationID: conversationID, messageID: messageID, viewMode: .full)
    }

    func getMessages(owner: KeyPair, conversationID: ConversationID, before: MessageID?) async throws -> [ConversationMessage] {
        try await getMessages(owner: owner, conversationID: conversationID, before: before, viewMode: .full)
    }

    func getDelta(
        owner: KeyPair,
        conversationID: ConversationID,
        afterSequence: UInt64,
        onBatch: @MainActor @Sendable @escaping (_ messages: [ConversationMessage], _ checkpoint: UInt64?) -> Void
    ) async throws -> UInt64 {
        try await getDelta(owner: owner, conversationID: conversationID, afterSequence: afterSequence, viewMode: .full, onBatch: onBatch)
    }
}

extension FlipClient: ContactVerifying, OnrampAuthorizing, ContactSyncing,
                      ConversationFetching, ConversationMembership, ConversationMessaging,
                      ConversationViewerSettings, ConversationEventStreaming {}
