//
//  ApplePayIdleTimerTests.swift
//  FlipcashTests
//

import Testing
@testable import Flipcash

@MainActor
@Suite("ApplePayIdleTimer")
struct ApplePayIdleTimerTests {

    @Test("arm fires the callback after the timeout elapses")
    func armedTimer_firesAfterTimeout() async {
        let timer = ApplePayIdleTimer(timeout: .milliseconds(50))
        var fired = false
        timer.arm { fired = true }

        try? await Task.sleep(for: .milliseconds(10))
        #expect(!fired, "timer fired before the timeout elapsed")

        try? await Task.sleep(for: .milliseconds(200))
        #expect(fired)
    }

    @Test("disarm prevents the callback from firing")
    func disarmedTimer_doesNotFire() async {
        let timer = ApplePayIdleTimer(timeout: .milliseconds(50))
        var fired = false
        timer.arm { fired = true }
        timer.disarm()

        try? await Task.sleep(for: .milliseconds(200))

        #expect(!fired)
    }

    @Test("re-arming cancels the previous pending callback")
    func reArm_cancelsPreviousCallback() async {
        let timer = ApplePayIdleTimer(timeout: .milliseconds(50))
        var firstFired = false
        var secondFired = false
        timer.arm { firstFired = true }
        timer.arm { secondFired = true }

        try? await Task.sleep(for: .milliseconds(200))

        #expect(!firstFired)
        #expect(secondFired)
    }

    @Test("disarm is idempotent and the timer remains armable after")
    func disarm_calledTwice_remainsArmable() async {
        let timer = ApplePayIdleTimer(timeout: .milliseconds(50))
        timer.arm { }
        timer.disarm()
        timer.disarm()

        var fired = false
        timer.arm { fired = true }
        try? await Task.sleep(for: .milliseconds(200))
        #expect(fired)
    }
}
