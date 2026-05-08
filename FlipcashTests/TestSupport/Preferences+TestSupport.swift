//
//  Preferences+TestSupport.swift
//  FlipcashTests
//
//  Created by Raul Riera on 2026-05-08.
//

import Foundation
import FlipcashCore
@testable import Flipcash

extension Preferences {
    /// Test-only initialiser that bypasses the shared UserDefaults read
    /// and seeds the timeout directly. Production callers go through
    /// `init()` which reads from `UserDefaults.standard`.
    static func forTesting(autoReturnTimeout: AutoReturnTimeout) -> Preferences {
        let p = Preferences()
        p.autoReturnTimeout = autoReturnTimeout
        return p
    }
}
