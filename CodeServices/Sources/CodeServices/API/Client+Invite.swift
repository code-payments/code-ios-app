//
//  Client+Invite.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

extension Client {
    
    public func redeem(inviteCode: String, for phoneNumber: Phone) async throws {
        try await withCheckedThrowingContinuation { c in
            inviteService.redeem(inviteCode: inviteCode, for: phoneNumber) { c.resume(with: $0) }
        }
    }
    
    public func whitelist(phoneNumber: Phone, userID: ID) async throws {
        try await withCheckedThrowingContinuation { c in
            inviteService.whitelist(phoneNumber: phoneNumber, userID: userID) { c.resume(with: $0) }
        }
    }
    
    public func fetchInviteCount(userID: ID) async throws -> Int {
        try await withCheckedThrowingContinuation { c in
            inviteService.fetchInviteCount(userID: userID) { c.resume(with: $0) }
        }
    }
    
    public func fetchInviteStatus(userID: ID) async throws -> InvitationStatus {
        try await withCheckedThrowingContinuation { c in
            inviteService.fetchInviteStatus(userID: userID) { c.resume(with: $0) }
        }
    }
}
