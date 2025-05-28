//
//  FlipClient+Push.swift
//  FlipcashCore
//
//  Created by Dima Bart on 2025-04-16.
//

import Foundation

extension FlipClient {
    
    public func addToken(token: String, installationID: String, owner: KeyPair) async throws {
        try await withCheckedThrowingContinuation { c in
            pushService.addToken(token: token, installationID: installationID, owner: owner) { c.resume(with: $0) }
        }
    }
    
    public func deleteTokens(installationID: String, owner: KeyPair) async throws {
        try await withCheckedThrowingContinuation { c in
            pushService.deleteTokens(installationID: installationID, owner: owner) { c.resume(with: $0) }
        }
    }
}
