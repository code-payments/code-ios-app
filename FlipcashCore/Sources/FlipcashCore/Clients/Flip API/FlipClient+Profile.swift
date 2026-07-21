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

    /// Sets the caller's display name, which the server moderates before it
    /// persists.
    public func setDisplayName(_ displayName: String, owner: KeyPair) async throws {
        try await profileService.setDisplayName(displayName, owner: owner)
    }

    /// Attaches an already-finalized blob as the caller's profile picture.
    public func setProfilePicture(blobID: BlobID, owner: KeyPair) async throws {
        try await profileService.setProfilePicture(blobID: blobID, owner: owner)
    }
}
