//
//  FlipClient+Profile.swift
//  FlipcashCore
//
//  Created by Dima Bart on 2025-04-16.
//

import Foundation

extension FlipClient {
    
    public func fetchProfile(userID: UserID, owner: KeyPair) async throws -> Profile {
        try await withCheckedThrowingContinuation { c in
            profileService.fetchProfile(userID: userID, owner: owner) { c.resume(with: $0) }
        }
    }
}
