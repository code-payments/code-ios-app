//
//  FlipClient+ThirdParty.swift
//  FlipcashCore
//
//  Created by Dima Bart on 2025-04-16.
//

import Foundation

extension FlipClient {
    
    public func fetchCoinbaseOnrampJWT(apiKey: String, owner: KeyPair, method: String, path: String) async throws -> String {
        try await withCheckedThrowingContinuation { c in
            thirdPartyService.fetchCoinbaseOnrampJWT(apiKey: apiKey, owner: owner, method: method, path: path) { c.resume(with: $0) }
        }
    }
}
