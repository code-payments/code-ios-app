//
//  FlipchatClient+Account.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

extension FlipchatClient {
    
    public func register(name: String?, owner: KeyPair) async throws -> UserID {
        try await withCheckedThrowingContinuation { c in
            accountService.register(name: name, owner: owner) { c.resume(with: $0) }
        }
    }
    
    public func fetchPaymentDestination(userID: UserID) async throws -> PublicKey {
        try await withCheckedThrowingContinuation { c in
            accountService.fetchPaymentDestination(userID: userID) { c.resume(with: $0) }
        }
    }
    
    public func fetchUserFlags(userID: UserID, owner: KeyPair) async throws -> UserFlags {
        try await withCheckedThrowingContinuation { c in
            accountService.fetchUserFlags(userID: userID, owner: owner) { c.resume(with: $0) }
        }
    }
}
