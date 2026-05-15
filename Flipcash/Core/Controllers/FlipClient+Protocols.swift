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

/// Phone and email verification surface used by `VerificationOperation`.
/// Each method maps 1:1 to a Flipcash backend RPC; the operation drives the
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

extension FlipClient: ContactVerifying, OnrampAuthorizing {}
