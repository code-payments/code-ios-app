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

/// DM conversation read surface used by `ConversationController` — the feed plus a
/// single conversation by id. Maps 1:1 to the `flipcash.chat.v1.Chat` RPCs.
protocol ConversationFetching: AnyObject, Sendable {
    func getDmChatFeed(owner: KeyPair) async throws -> [Conversation]
    func getChat(owner: KeyPair, conversationID: ConversationID) async throws -> Conversation
}

/// DM message send/read surface used by `ConversationController`. Maps to the
/// `flipcash.messaging.v1.Messaging` RPCs.
protocol ConversationMessaging: AnyObject, Sendable {
    /// Fetches a page of messages. `before == nil` returns the newest page;
    /// pass the oldest currently-loaded id to page strictly older (history).
    func getMessages(owner: KeyPair, conversationID: ConversationID, before: MessageID?) async throws -> [ConversationMessage]
    func sendMessage(owner: KeyPair, conversationID: ConversationID, text: String, clientMessageID: UUID) async throws -> ConversationMessage
    func markRead(owner: KeyPair, conversationID: ConversationID, messageID: MessageID) async throws
}

/// The single per-user event stream surface used by `ConversationController`. Wraps the
/// `event.v1 StreamEvents` lifecycle behind `ConversationStreamEvent`.
protocol ConversationEventStreaming: AnyObject, Sendable {
    func openConversationStream(owner: KeyPair) -> AsyncStream<ConversationStreamEvent>
    func ensureConversationStreamConnected()
    func closeConversationStream()
}

extension FlipClient: ContactVerifying, OnrampAuthorizing, ContactSyncing,
                      ConversationFetching, ConversationMessaging,
                      ConversationEventStreaming {}
