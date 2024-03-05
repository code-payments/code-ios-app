//
//  Client+Device.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

extension Client {

    public func registerInstallation(for owner: KeyPair, installationID: String) async throws {
        try await withCheckedThrowingContinuation { c in
            deviceService.registerInstallation(for: owner, installationID: installationID) { c.resume(with: $0) }
        }
    }
    
    public func fetchInstallationAccounts(for installationID: String) async throws -> [PublicKey] {
        try await withCheckedThrowingContinuation { c in
            deviceService.fetchInstallationAccounts(for: installationID) { c.resume(with: $0) }
        }
    }
}
