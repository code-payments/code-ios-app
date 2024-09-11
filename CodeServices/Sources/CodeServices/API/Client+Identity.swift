//
//  Client+Identity.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

extension Client {
    
    public func linkAccount(phone: Phone, code: String, owner: KeyPair) async throws {
        try await withCheckedThrowingContinuation { c in
            identityService.linkAccount(phone: phone, code: code, owner: owner) { c.resume(with: $0) }
        }
    }
    
    public func unlinkAccount(phone: Phone, owner: KeyPair) async throws {
        try await withCheckedThrowingContinuation { c in
            identityService.unlinkAccount(phone: phone, owner: owner) { c.resume(with: $0) }
        }
    }
    
    public func fetchUser(phone: Phone, owner: KeyPair) async throws -> User {
        try await withCheckedThrowingContinuation { c in
            identityService.fetchUser(phone: phone, owner: owner) { c.resume(with: $0) }
        }
    }
    
    public func fetchTwitterUser(owner: KeyPair, query: TwitterUserQuery) async throws -> TwitterUser {
        try await withCheckedThrowingContinuation { c in
            identityService.fetchTwitterUser(owner: owner, query: query) { c.resume(with: $0) }
        }
    }
    
    public func loginToThirdParty(rendezvous: PublicKey, relationship: KeyPair) async throws {
        try await withCheckedThrowingContinuation { c in
            identityService.loginToThirdParty(rendezvous: rendezvous, relationship: relationship) { c.resume(with: $0) }
        }
    }
    
    public func updatePreferences(user: User, locale: Locale, owner: KeyPair) async throws {
        try await withCheckedThrowingContinuation { c in
            identityService.updatePreferences(user: user, locale: locale, owner: owner) { c.resume(with: $0) }
        }
    }
}
