//
//  FlipClient+Protocols.swift
//  FlipcashCore
//

import Foundation

/// Phone and email verification surface used by `VerificationOperation`.
/// Each method maps 1:1 to a Flipcash backend RPC; the operation drives the
/// state machine and the conformer issues the calls.
public protocol ContactVerifying: AnyObject {

    func sendVerificationCode(phone: String, owner: KeyPair) async throws
    func checkVerificationCode(phone: String, code: String, owner: KeyPair) async throws

    func sendEmailVerification(email: String, owner: KeyPair) async throws
    func checkEmailCode(email: String, code: String, owner: KeyPair) async throws
}

/// Coinbase CDP JWT minting surface used by the session-scoped Coinbase
/// service. JWTs are URI-bound so each request needs one signed for that
/// exact method/path or Coinbase rejects with 401.
public protocol OnrampAuthorizing: AnyObject {

    func fetchCoinbaseOnrampJWT(
        apiKey: String,
        owner: KeyPair,
        method: String,
        path: String
    ) async throws -> String
}

extension FlipClient: ContactVerifying, OnrampAuthorizing {}
