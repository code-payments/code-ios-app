//
//  FlipClient+Account.swift
//  FlipcashCore
//
//  Created by Dima Bart on 2025-04-16.
//

import Foundation

extension FlipClient {
    
    @discardableResult
    public func register(owner: KeyPair) async throws -> UserID {
        try await withCheckedThrowingContinuation { c in
            accountService.register(owner: owner) { c.resume(with: $0) }
        }
    }
    
    public func login(owner: KeyPair) async throws -> UserID {
        try await withCheckedThrowingContinuation { c in
            accountService.login(owner: owner) { c.resume(with: $0) }
        }
    }
    
    public func fetchUserFlags(userID: UserID, owner: KeyPair) async throws -> UserFlags {
        try await withCheckedThrowingContinuation { c in
            accountService.fetchUserFlags(userID: userID, owner: owner) { c.resume(with: $0) }
        }
    }

    public func fetchUnauthenticatedUserFlags() async throws -> UnauthenticatedUserFlags {
        try await withCheckedThrowingContinuation { c in
            accountService.fetchUnauthenticatedUserFlags { c.resume(with: $0) }
        }
    }
}
