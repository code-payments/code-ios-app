//
//  Client+Balance.swift
//  FlipcashCore
//

import Foundation
import FlipcashAPI

extension Client {
    /// Fetches the core-mint balance for any owner account. No signature is
    /// required — the server allows reading balance for any owner.
    public func getBalance(owner: PublicKey) async throws -> TokenAmount {
        try await withCheckedThrowingContinuation { c in
            balanceService.getBalance(owner: owner) { c.resume(with: $0) }
        }
    }
}
