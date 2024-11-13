//
//  Client+Badge.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

extension Client {
    
    public func resetBadgeCount(for owner: KeyPair) async throws {
        try await withCheckedThrowingContinuation { c in
            badgeService.resetBadgeCount(owner: owner) { c.resume(with: $0) }
        }
    }
}
