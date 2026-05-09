//
//  Tags+TestSupport.swift
//  FlipcashTests
//

import Testing

extension Tag {
    /// Marks a test as exercising actor isolation, race detection, or
    /// other concurrency-correctness properties. Useful for filtering
    /// these tests under TSan + Main Thread Checker in CI.
    @Tag static var concurrency: Self

    /// Marks a stress test that runs a large number of operations to
    /// exercise contention. Pair with `.concurrency` when applicable.
    @Tag static var stress: Self
}
