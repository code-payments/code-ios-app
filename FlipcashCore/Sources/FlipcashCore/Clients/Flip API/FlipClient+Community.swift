//
//  FlipClient+Community.swift
//  FlipcashCore
//

import Foundation

extension FlipClient {

    /// Fetches the community of the currency launched as `mint`. Throws
    /// `ErrorGetCommunity.notFound` when the mint is not a Flipcash currency.
    public func fetchCommunity(mint: PublicKey, owner: KeyPair) async throws -> Community {
        try await withCheckedThrowingContinuation { c in
            communityService.getCommunity(mint: mint, owner: owner) { c.resume(with: $0) }
        }
    }
}
