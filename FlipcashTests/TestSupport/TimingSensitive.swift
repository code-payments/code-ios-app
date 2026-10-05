//
//  TimingSensitive.swift
//  FlipcashTests
//

import Foundation
import Testing

extension Trait where Self == ConditionTrait {
    /// Disables a test under the Sanitizers plan, which sets `FLIPCASH_TSAN`.
    ///
    /// For tests that assert on wall-clock bounds or sample animation frames:
    /// Thread Sanitizer slows the main actor enough that they miss, and that plan
    /// has no retries. `AllTargets` still runs them.
    static var timingSensitive: Self {
        .disabled(
            if: ProcessInfo.processInfo.environment["FLIPCASH_TSAN"] == "1",
            "Asserts on wall-clock timing, which Thread Sanitizer distorts"
        )
    }
}
