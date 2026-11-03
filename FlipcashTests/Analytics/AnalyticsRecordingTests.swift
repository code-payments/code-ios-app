//
//  AnalyticsRecordingTests.swift
//  FlipcashTests
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("Analytics recording in parallel tests")
struct AnalyticsRecordingTests {

    /// Holds the outer recording at a known suspension point and keeps what it recorded.
    @MainActor
    private final class Gate {
        var continuation: CheckedContinuation<Void, Never>?
        var outerSent: [SentEvent] = []
    }

    @Test("A recording keeps its events while another recording starts and ends during it")
    func overlappingRecordings() async throws {
        let gate = Gate()
        let outer = Task {
            gate.outerSent = await Analytics.recordingSendsAsync {
                await withCheckedContinuation { gate.continuation = $0 }
                Analytics.track(DeeplinkEvents.shared.open(url: "outer"))
            }
        }
        while gate.continuation == nil { await Task.yield() }

        let inner = Analytics.recordingSends {
            Analytics.track(DeeplinkEvents.shared.open(url: "inner"))
        }
        gate.continuation?.resume()
        await outer.value

        #expect(try gate.outerSent.single.properties["URL"] as? String == "outer")
        #expect(try inner.single.properties["URL"] as? String == "inner")
    }
}
