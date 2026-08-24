//
//  FlipClient+Profile.swift
//  FlipcashCore
//
//  Created by Dima Bart on 2025-04-16.
//

import Foundation

extension FlipClient {
    
    public func fetchProfile(userID: UserID, owner: KeyPair) async throws -> Profile {
        try await fetchProfile(.userID(userID), owner: owner)
    }

    /// Fetches the profile behind a claimed handle. The response carries the
    /// user's id, so a caller holding only a handle learns it from the result.
    public func fetchProfile(username: Username, owner: KeyPair) async throws -> Profile {
        try await fetchProfile(.username(username), owner: owner)
    }

    private func fetchProfile(_ identifier: ProfileIdentifier, owner: KeyPair) async throws -> Profile {
        try await withCheckedThrowingContinuation { c in
            profileService.fetchProfile(identifier, owner: owner) { c.resume(with: $0) }
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

    /// Updates the caller's Tip Card customization. The server validates the
    /// colour and falls back to the default for anything left unset.
    public func updateTipCard(_ customization: TipCardCustomization, owner: KeyPair) async throws {
        try await profileService.updateTipCard(color: customization.colorProto, owner: owner)
    }
}
