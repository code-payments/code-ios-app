//
//  Client+Account.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

extension Client {
    
    public func fetchIsCodeAccount(owner: KeyPair) async throws -> Bool {
        try await withCheckedThrowingContinuation { c in
            accountService.fetchIsCodeAccount(owner: owner) { c.resume(with: $0) }
        }
    }
    
    public func fetchAccountInfos(owner: KeyPair) async throws -> [PublicKey: AccountInfo] {
        try await withCheckedThrowingContinuation { c in
            accountService.fetchAccountInfos(owner: owner) { c.resume(with: $0) }
        }
    }
    
    public func linkAdditionalAccounts(owner: KeyPair, linkedAccount: KeyPair) async throws {
        try await withCheckedThrowingContinuation { c in
            accountService.linkAdditionalAccounts(owner: owner, linkedAccount: linkedAccount) { c.resume(with: $0) }
        }
    }
}
