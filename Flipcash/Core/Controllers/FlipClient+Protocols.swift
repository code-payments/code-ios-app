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

    func streamFlipcashContacts(checksum: Data, owner: KeyPair) -> AsyncThrowingStream<String, Error>
}

extension FlipClient: ContactVerifying, OnrampAuthorizing, ContactSyncing {}
