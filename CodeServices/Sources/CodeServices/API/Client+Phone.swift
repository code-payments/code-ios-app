//
//  Client+Phone.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

extension Client {

    public func sendCode(phone: Phone) async throws {
        try await withCheckedThrowingContinuation { c in
            phoneService.sendCode(phone: phone) { c.resume(with: $0) }
        }
    }
    
    public func validate(phone: Phone, code: String) async throws {
        try await withCheckedThrowingContinuation { c in
            phoneService.validate(phone: phone, code: code) { c.resume(with: $0) }
        }
    }
    
    public func fetchAssociatedPhoneNumber(owner: KeyPair) async throws -> PhoneLink {
        try await withCheckedThrowingContinuation { c in
            phoneService.fetchAssociatedPhoneNumber(owner: owner) { c.resume(with: $0) }
        }
    }
}
