//
//  FlipchatClient+Push.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

extension FlipchatClient {
    
    public func addToken(token: String, installationID: String, owner: KeyPair) async throws {
        try await withCheckedThrowingContinuation { c in
            pushService.addToken(token: token, installationID: installationID, owner: owner) { c.resume(with: $0) }
        }
    }
    
    public func deleteToken(token: String, owner: KeyPair) async throws {
        try await withCheckedThrowingContinuation { c in
            pushService.deleteToken(token: token, owner: owner) { c.resume(with: $0) }
        }
    }
}
