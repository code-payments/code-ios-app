//
//  FlipchatClient+Profile.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

extension FlipchatClient {
    
    public func fetchProfile(userID: UserID) async throws -> UserProfile {
        try await withCheckedThrowingContinuation { c in
            profileService.fetchProfile(userID: userID) { c.resume(with: $0) }
        }
    }
    
    public func setDisplayName(name: String, owner: KeyPair) async throws {
        try await withCheckedThrowingContinuation { c in
            profileService.setDisplayName(name: name, owner: owner) { c.resume(with: $0) }
        }
    }
    
    public func linkSocialAccount(token: String, owner: KeyPair) async throws -> Chat.SocialProfile {
        try await withCheckedThrowingContinuation { c in
            profileService.linkSocialAccount(token: token, owner: owner) { c.resume(with: $0) }
        }
    }
    
    public func unlinkSocialAccount(socialID: String, owner: KeyPair) async throws {
        try await withCheckedThrowingContinuation { c in
            profileService.unlinkSocialAccount(socialID: socialID, owner: owner) { c.resume(with: $0) }
        }
    }
}
