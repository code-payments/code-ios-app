//
//  Database+TestSupport.swift
//  FlipcashTests
//

import Foundation
@testable import Flipcash

extension Database {
    /// Build a fresh SQLite-backed `Database` rooted in `NSTemporaryDirectory()`
    /// with a unique filename. Safe to call from any test without cleanup —
    /// each invocation is isolated.
    static func makeTemp() throws -> Database {
        try Database(url: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("test-\(UUID().uuidString).sqlite"))
    }
}
