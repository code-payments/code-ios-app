//
//  Keychain+TestSupport.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import FlipcashCore

extension Keychain {
    /// The shared access group resolved at runtime; throws (skipping the test cleanly) when the
    /// simulator keychain can't resolve it.
    static func requireSharedAccessGroup() throws -> String {
        try #require(Keychain.sharedAccessGroup, "Shared access group must resolve at runtime")
    }
}
