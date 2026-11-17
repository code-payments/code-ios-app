//
//  FlipClient+Email.swift
//  FlipcashCore
//
//  Created by Dima Bart on 2025-04-16.
//

import Foundation

extension FlipClient {
    
    public func sendEmailVerification(email: String, owner: KeyPair) async throws {
        try await withCheckedThrowingContinuation { c in
            emailService.sendEmailVerification(email: email, owner: owner) { c.resume(with: $0) }
        }
    }
    
    public func checkEmailCode(email: String, code: String, owner: KeyPair) async throws {
        try await withCheckedThrowingContinuation { c in
            emailService.checkEmailCode(email: email, code: code, owner: owner) { c.resume(with: $0) }
        }
    }
    
    public func unlinkEmail(email: String, owner: KeyPair) async throws {
        try await withCheckedThrowingContinuation { c in
            emailService.unlinkEmail(email: email, owner: owner) { c.resume(with: $0) }
        }
    }

    /// Links `email` without verifying it. The profile then reports the address
    /// with `isEmailAddressVerified == false`.
    public func linkUnverifiedEmail(email: String, owner: KeyPair) async throws {
        try await withCheckedThrowingContinuation { c in
            emailService.linkUnverifiedEmail(email: email, owner: owner) { c.resume(with: $0) }
        }
    }
}
