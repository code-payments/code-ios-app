//
//  FlipClient+Resolver.swift
//  FlipcashCore
//

import Foundation

extension FlipClient {

    /// Resolve a contact's E.164 phone to the Flipcash payment destination.
    /// Throws `.notFound` when not registered with Flipcash; throws for
    /// other hard failures.
    public func resolvePhone(_ e164: String, owner: KeyPair) async throws -> PublicKey {
        try await withCheckedThrowingContinuation { c in
            resolverService.resolvePhone(e164, owner: owner) { c.resume(with: $0) }
        }
    }

    /// Resolve a user ID to the Flipcash payment destination.
    /// Throws `.notFound` when no such user exists; throws for other hard
    /// failures.
    public func resolveUserID(_ userID: UserID, owner: KeyPair) async throws -> PublicKey {
        try await withCheckedThrowingContinuation { c in
            resolverService.resolveUserID(userID, owner: owner) { c.resume(with: $0) }
        }
    }
}
