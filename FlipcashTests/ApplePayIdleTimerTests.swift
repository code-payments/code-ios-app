//
//  ApplePayIdleTimerTests.swift
//  FlipcashTests
//

import Testing
@testable import Flipcash

/// These tests `await` the timer's onExpiry callback directly rather than
/// sleeping a fixed wall-clock budget. Under TSan + parallel @MainActor test
/// execution, MainActor contention can stretch a "200ms" sleep to multiple
/// seconds, so any timing-budgeted assertion is flaky. Waiting on the
/// callback itself bounds the test by the per-test execution timeout instead.
@MainActor
@Suite("ApplePayIdleTimer")
struct ApplePayIdleTimerTests {

    @Test("arm fires the callback after the timeout elapses")
    func armedTimer_firesAfterTimeout() async {
        let timer = ApplePayIdleTimer(timeout: .milliseconds(50))
        await withCheckedContinuation { continuation in
            timer.arm { continuation.resume() }
        }
    }

    @Test("disarm prevents the callback from firing")
    func disarmedTimer_doesNotFire() async {
        let timer = ApplePayIdleTimer(timeout: .milliseconds(50))
        await confirmation("disarmed callback does not fire", expectedCount: 0) { confirm in
            timer.arm { confirm() }
            timer.disarm()
            try? await Task.sleep(for: .seconds(1))
        }
    }

    @Test("re-arming cancels the previous pending callback")
    func reArm_cancelsPreviousCallback() async {
        let timer = ApplePayIdleTimer(timeout: .milliseconds(50))
        await confirmation("first callback does not fire", expectedCount: 0) { firstCallback in
            await withCheckedContinuation { continuation in
                timer.arm { firstCallback() }
                timer.arm { continuation.resume() }
            }
        }
    }

    @Test("disarm is idempotent and the timer remains armable after")
    func disarm_calledTwice_remainsArmable() async {
        let timer = ApplePayIdleTimer(timeout: .milliseconds(50))
        timer.arm { }
        timer.disarm()
        timer.disarm()

        await withCheckedContinuation { continuation in
            timer.arm { continuation.resume() }
        }
    }
}
