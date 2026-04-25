//
//  PingTrackerTests.swift
//  FlipcashTests
//

import Foundation
import Testing
@testable import FlipcashCore

@Suite("PingTracker")
struct PingTrackerTests {

    // MARK: - hasRecentPing -

    @Test("No ping received returns not recent")
    func noPing() {
        let tracker = PingTracker()
        #expect(tracker.lastPing == nil)
        #expect(!tracker.hasRecentPing)
    }

    @Test("Ping just received returns recent")
    func freshPing() {
        var tracker = PingTracker()
        tracker.receivedPing()
        #expect(tracker.hasRecentPing)
    }

    @Test("Stale ping returns not recent")
    func stalePing() {
        var tracker = PingTracker()
        tracker.lastPing = Date.now.addingTimeInterval(-20)
        #expect(!tracker.hasRecentPing)
    }

    // MARK: - timeoutSeconds -

    @Test("Default timeout is 15 seconds")
    func defaultTimeout() {
        let tracker = PingTracker()
        #expect(tracker.timeoutSeconds == 15)
    }

    @Test("Timeout doubles server value")
    func doubledTimeout() {
        var tracker = PingTracker()
        tracker.receivedPing(updatedTimeout: 10)
        #expect(tracker.timeoutSeconds == 20)
    }

    @Test("Timeout unchanged when server omits value")
    func timeoutPreserved() {
        var tracker = PingTracker()
        tracker.receivedPing(updatedTimeout: 5) // timeoutSeconds = 10
        tracker.receivedPing()                  // no updatedTimeout
        #expect(tracker.timeoutSeconds == 10)
    }

    @Test(
        "receivedPing returns the current timeout",
        arguments: [
            (input: Optional<Int>.none, expected: 15),
            (input: Optional<Int>.some(10), expected: 20),
        ]
    )
    func returnedTimeout(input: Int?, expected: Int) {
        var tracker = PingTracker()
        let returned = tracker.receivedPing(updatedTimeout: input)
        #expect(returned == expected)
    }
}
