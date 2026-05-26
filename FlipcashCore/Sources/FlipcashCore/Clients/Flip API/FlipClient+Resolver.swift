//
//  FlipClient+Resolver.swift
//  FlipcashCore
//

import Foundation

extension FlipClient {

    /// Resolve a contact's E.164 phone to the Flipcash payment destination.
    /// Returns `nil` for NOT_FOUND (not registered with Flipcash); throws for
    /// hard failures.
    public func resolvePhone(_ e164: String, owner: KeyPair) async throws -> PublicKey? {
        try await withCheckedThrowingContinuation { c in
            resolverService.resolvePhone(e164, owner: owner) { c.resume(with: $0) }
        }
    }
}
