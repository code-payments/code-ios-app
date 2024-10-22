//
//  FlipchatClient+Account.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import CodeServices

extension FlipchatClient {
    
    public func register(name: String?, owner: KeyPair) async throws -> UserID {
        try await withCheckedThrowingContinuation { c in
            accountService.register(name: name, owner: owner) { c.resume(with: $0) }
        }
    }
}
