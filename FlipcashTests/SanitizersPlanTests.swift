//
//  SanitizersPlanTests.swift
//  FlipcashTests
//

import Foundation
import Testing

/// Guards the `Sanitizers` test plan's settings that keep the release gate passing.
///
/// Under Thread Sanitizer the main thread is the bottleneck: run in parallel, every
/// `@MainActor` test queues on it, victims wait ~50 s, and tests with wall-clock bounds
/// (`.timeLimit`, poll deadlines) fail. Run serially, the plan passes. See `.claude/plans/2026-11-12-tsan-nio-bytebuffer-race.md`.
@Suite("Sanitizers test plan")
struct SanitizersPlanTests {

    private static let plan = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // FlipcashTests
        .appending(path: "Sanitizers.xctestplan")

    @Test("no target runs its tests in parallel")
    func noTargetIsParallelizable() throws {
        let data = try Data(contentsOf: Self.plan)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let targets = try #require(json["testTargets"] as? [[String: Any]])
        try #require(!targets.isEmpty)

        for target in targets {
            let name = (target["target"] as? [String: Any])?["name"] as? String ?? "?"
            // A missing key runs the target in parallel, so require an explicit `false`.
            #expect(target["parallelizable"] as? Bool == false, "\(name) is parallelizable")
        }
    }
}
