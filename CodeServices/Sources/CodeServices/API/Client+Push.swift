//
//  Client+Push.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

extension Client {
    
    public func addToken(firebaseToken: String, containerID: ID, owner: KeyPair, installationID: String) async throws {
        try await withCheckedThrowingContinuation { c in
            pushService.addToken(firebaseToken: firebaseToken, containerID: containerID, owner: owner, installationID: installationID) { c.resume(with: $0) }
        }
    }
}
