//
//  FlipClient+Phone.swift
//  FlipcashCore
//
//  Created by Dima Bart on 2025-04-16.
//

import Foundation

extension FlipClient {
    
    public func sendVerificationCode(phone: String, owner: KeyPair) async throws {
        try await withCheckedThrowingContinuation { c in
            phoneService.sendVerificationCode(phone: phone, owner: owner) { c.resume(with: $0) }
        }
    }
    
    public func checkVerificationCode(phone: String, code: String, owner: KeyPair) async throws {
        try await withCheckedThrowingContinuation { c in
            phoneService.checkVerificationCode(phone: phone, code: code, owner: owner) { c.resume(with: $0) }
        }
    }
}
