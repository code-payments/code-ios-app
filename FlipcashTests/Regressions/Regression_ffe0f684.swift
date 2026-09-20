//
//  Regression_ffe0f684.swift
//  Flipcash
//
//  Symptom:  RUNNINGBOARD 0xdead10cc SIGKILL. Session's 10s poller kept firing
//            after the app backgrounded; a tick's `database.transaction` held a
//            SQLite write lock on the App Group store when iOS suspended us.
//
//  Fix:      Poller gains cancel() + waitUntilFinished(). didEnterBackground()
//            cancels so no new tick starts; AppDelegate awaits the in-flight one
//            inside the background-task assertion before checkpointing.
//

import Foundation
import Testing
import FlipcashCore

/// Tracks whether the poller's action is currently executing.
private actor ActionTracker {
    private(set) var isRunning = false
    private(set) var completedCount = 0

    func begin() {
        isRunning = true
    }

    func end() {
        isRunning = false
        completedCount += 1
    }
}

@Suite("Regression: ffe0f684 – Poller drains in-flight work before suspension", .bug("FFE0F684-681B-44A2-AA12-36FD00D03549"))
struct Regression_ffe0f684 {

    @Test("waitUntilFinished() does not return while an action is still in flight")
    func drain_waitsForInFlightAction() async {
        let tracker = ActionTracker()
        let poller = Poller(seconds: 60, fireImmediately: true) {
            await tracker.begin()
            try? await Task.sleep(for: .milliseconds(200))
            await tracker.end()
        }

        // Let the immediate tick get into the action body.
        try? await Task.sleep(for: .milliseconds(50))
        #expect(await tracker.isRunning)

        poller.cancel()
        await poller.waitUntilFinished()

        // The load-bearing assertion: a waitUntilFinished() that only cancels
        // without awaiting the task would return here with isRunning still true.
        #expect(await tracker.isRunning == false)
        #expect(await tracker.completedCount == 1)
    }

    @Test("cancel() while sleeping stops the loop without running another action")
    func cancel_whileSleeping_runsNoFurtherAction() async {
        let tracker = ActionTracker()
        let poller = Poller(seconds: 60, fireImmediately: true) {
            await tracker.begin()
            await tracker.end()
        }

        // The immediate tick is over; the loop is now in Task.sleep(60s).
        try? await Task.sleep(for: .milliseconds(100))
        #expect(await tracker.completedCount == 1)

        poller.cancel()
        await poller.waitUntilFinished()

        #expect(await tracker.completedCount == 1)
    }
}
