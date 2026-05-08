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
    /// Constructs a `Preferences` and seeds `autoReturnTimeout`. The seed
    /// value is persisted via the normal `willSet` write to
    /// `UserDefaults.standard`, so callers should clear that key in
    /// teardown if they want isolation.
    static func forTesting(autoReturnTimeout: AutoReturnTimeout) -> Preferences {
        let preferences = Preferences()
        preferences.autoReturnTimeout = autoReturnTimeout
        return preferences
    }
}
