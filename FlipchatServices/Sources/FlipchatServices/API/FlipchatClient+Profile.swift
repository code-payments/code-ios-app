//
//  FlipchatClient+Profile.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

extension FlipchatClient {
    
    public func fetchProfile(userID: UserID) async throws -> String? {
        try await withCheckedThrowingContinuation { c in
            profileService.fetchProfile(userID: userID) { c.resume(with: $0) }
        }
    }
    
    public func setDisplayName(name: String, owner: KeyPair) async throws {
        try await withCheckedThrowingContinuation { c in
            profileService.setDisplayName(name: name, owner: owner) { c.resume(with: $0) }
        }
    }
}
