//
//  Database+TestSupport.swift
//  FlipcashTests
//

import Foundation
@testable import Flipcash

extension Database {

    /// Creates an isolated, per-test SQLite database under the system temp directory.
    /// Each call returns a fresh `Database` backed by a unique file path so concurrent
    /// tests do not share state through `Database.mock`.
    ///
    /// Callers don't need to clean up — the OS reaps the temp directory eventually,
    /// and the file path is unique per call.
    static func makeIsolated() throws -> Database {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("test-\(UUID().uuidString).sqlite")
        return try Database(url: url)
    }
}
