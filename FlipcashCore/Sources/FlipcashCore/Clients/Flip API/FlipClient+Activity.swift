//
//  FlipClient+Activity.swift
//  FlipcashCore
//
//  Created by Dima Bart on 2025-04-16.
//

import Foundation

extension FlipClient {
    
    public func fetchTransactionHistory(owner: KeyPair, pageSize: Int, since cursor: PublicKey?) async throws -> [Activity] {
        try await withCheckedThrowingContinuation { c in
            activityService.fetchTransactionHistory(owner: owner, pageSize: pageSize, since: cursor) { c.resume(with: $0) }
        }
    }
    
    public func fetchTransactionHistoryItemsByID(owner: KeyPair, ids: [PublicKey]) async throws -> [Activity] {
        try await withCheckedThrowingContinuation { c in
            activityService.fetchTransactionHistoryItemsByID(owner: owner, ids: ids) { c.resume(with: $0) }
        }
    }
}
