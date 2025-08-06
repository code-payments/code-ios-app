//
//  FlipClient+ThirdParty.swift
//  FlipcashCore
//
//  Created by Dima Bart on 2025-04-16.
//

import Foundation

extension FlipClient {
    
    public func fetchCoinbaseOnrampJWT(apiKey: String, owner: KeyPair) async throws -> String {
        try await withCheckedThrowingContinuation { c in
            thirdPartyService.fetchCoinbaseOnrampJWT(apiKey: apiKey, owner: owner) { c.resume(with: $0) }
        }
    }
}
