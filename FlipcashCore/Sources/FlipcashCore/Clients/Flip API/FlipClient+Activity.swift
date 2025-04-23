//
//  FlipClient+Activity.swift
//  FlipcashCore
//
//  Created by Dima Bart on 2025-04-16.
//

import Foundation

extension FlipClient {
    
    public func fetchTransactionHistory(owner: KeyPair) async throws -> [Activity] {
        try await withCheckedThrowingContinuation { c in
            activityService.fetchTransactionHistory(owner: owner) { c.resume(with: $0) }
        }
    }
}
