//
//  FlipClient+IAP.swift
//  FlipcashCore
//
//  Created by Dima Bart on 2025-04-16.
//

import Foundation

extension FlipClient {
    
    public func createPool(poolMetadata: PoolMetadata, owner: KeyPair) async throws {
        try await withCheckedThrowingContinuation { c in
            poolService.createPool(poolMetadata: poolMetadata, owner: owner) { c.resume(with: $0) }
        }
    }
    
    public func fetchPool(poolID: PublicKey) async throws -> PoolDescription {
        try await withCheckedThrowingContinuation { c in
            poolService.fetchPool(poolID: poolID) { c.resume(with: $0) }
        }
    }
}
