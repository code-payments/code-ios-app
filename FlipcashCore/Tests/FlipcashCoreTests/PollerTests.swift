import Foundation
import Testing
import os
@testable import FlipcashCore

@Suite("Poller Tests")
struct PollerTests {

    @Test("fires immediately when fireImmediately is true")
    func firesImmediately() async {
        let fired = OSAllocatedUnfairLock(initialState: false)

        let poller = Poller(seconds: 60, fireImmediately: true) {
            fired.withLock { $0 = true }
        }

        try? await Task.sleep(for: .milliseconds(100))

        #expect(fired.withLock { $0 } == true)
        _ = poller
    }

    @Test("does not fire immediately when fireImmediately is false")
    func doesNotFireImmediately() async {
        let callCount = OSAllocatedUnfairLock(initialState: 0)

        let poller = Poller(seconds: 60, fireImmediately: false) {
            callCount.withLock { $0 += 1 }
        }

        try? await Task.sleep(for: .milliseconds(100))

        #expect(callCount.withLock { $0 } == 0)
        _ = poller
    }

    @Test("fires repeatedly on interval")
    func firesRepeatedly() async {
        let callCount = OSAllocatedUnfairLock(initialState: 0)

        let poller = Poller(seconds: 0.1, fireImmediately: false) {
            callCount.withLock { $0 += 1 }
        }

        try? await Task.sleep(for: .milliseconds(350))

        let count = callCount.withLock { $0 }
        #expect(count >= 2)
        _ = poller
    }

    @Test("stops firing after deallocation")
    func stopsOnDealloc() async throws {
        let callCount = OSAllocatedUnfairLock(initialState: 0)

        do {
            let poller = Poller(seconds: 0.05, fireImmediately: true) {
                callCount.withLock { $0 += 1 }
            }
            try? await Task.sleep(for: .milliseconds(200))
            _ = poller
        }

        let countAfterDealloc = callCount.withLock { $0 }
        try #require(countAfterDealloc > 0, "Poller should have fired at least once before deallocation")

        try? await Task.sleep(for: .milliseconds(200))
        let countLater = callCount.withLock { $0 }

        #expect(countAfterDealloc == countLater)
    }

    @Test("serializes actions - next poll waits for previous to finish")
    func serializedExecution() async {
        let maxConcurrent = OSAllocatedUnfairLock(initialState: 0)
        let currentConcurrent = OSAllocatedUnfairLock(initialState: 0)

        let poller = Poller(seconds: 0.05, fireImmediately: true) {
            let current = currentConcurrent.withLock { val -> Int in
                val += 1
                return val
            }
            maxConcurrent.withLock { val in
                val = max(val, current)
            }
            try? await Task.sleep(for: .milliseconds(50))
            currentConcurrent.withLock { $0 -= 1 }
        }

        try? await Task.sleep(for: .milliseconds(400))

        #expect(maxConcurrent.withLock { $0 } == 1)
        _ = poller
    }
}
