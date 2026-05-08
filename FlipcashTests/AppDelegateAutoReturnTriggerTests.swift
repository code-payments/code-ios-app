//
//  AppDelegateAutoReturnTriggerTests.swift
//  FlipcashTests
//
//  Created by Raul Riera on 2026-05-08.
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@Suite("AppDelegate Auto-Return Trigger")
struct AppDelegateAutoReturnTriggerTests {

    @Test("shouldReturnToRoot with elapsed time past timeout returns true")
    func shouldReturnToRoot_elapsedPastTimeout_returnsTrue() {
        let now = Date()
        let lastBackgroundedAt = Date(timeInterval: -360, since: now)  // 6 minutes ago

        let result = AppDelegate.shouldReturnToRoot(
            now: now,
            lastBackgroundedAt: lastBackgroundedAt,
            autoReturnTimeout: .fiveMinutes
        )

        #expect(result == true)
    }

    @Test("shouldReturnToRoot with elapsed time below timeout returns false")
    func shouldReturnToRoot_elapsedBelowTimeout_returnsFalse() {
        let now = Date()
        let lastBackgroundedAt = Date(timeInterval: -240, since: now)  // 4 minutes ago

        let result = AppDelegate.shouldReturnToRoot(
            now: now,
            lastBackgroundedAt: lastBackgroundedAt,
            autoReturnTimeout: .fiveMinutes
        )

        #expect(result == false)
    }

    @Test("shouldReturnToRoot at exact timeout boundary returns true")
    func shouldReturnToRoot_elapsedEqualsTimeout_returnsTrue() {
        let now = Date()
        let lastBackgroundedAt = Date(timeInterval: -300, since: now)  // exactly 5 minutes ago

        let result = AppDelegate.shouldReturnToRoot(
            now: now,
            lastBackgroundedAt: lastBackgroundedAt,
            autoReturnTimeout: .fiveMinutes
        )

        #expect(result == true, "boundary uses >= so equal-elapsed satisfies the trigger")
    }

    @Test("shouldReturnToRoot with elapsed time past tenMinutes timeout returns true")
    func shouldReturnToRoot_elevenMinutesElapsed_tenMinutesTimeout_returnsTrue() {
        let now = Date()
        let lastBackgroundedAt = Date(timeInterval: -660, since: now)  // 11 minutes ago

        let result = AppDelegate.shouldReturnToRoot(
            now: now,
            lastBackgroundedAt: lastBackgroundedAt,
            autoReturnTimeout: .tenMinutes
        )

        #expect(result == true)
    }

    @Test("shouldReturnToRoot with never timeout returns false regardless of elapsed time")
    func shouldReturnToRoot_neverTimeout_returnsFalse() {
        let now = Date()
        let lastBackgroundedAt = Date(timeInterval: -360, since: now)  // 6 minutes ago

        let result = AppDelegate.shouldReturnToRoot(
            now: now,
            lastBackgroundedAt: lastBackgroundedAt,
            autoReturnTimeout: .never
        )

        #expect(result == false, "never opts out of the auto-return trigger entirely")
    }

    @Test("shouldReturnToRoot with nil lastBackgroundedAt returns false")
    func shouldReturnToRoot_nilLastBackgroundedAt_returnsFalse() {
        let now = Date()

        let result = AppDelegate.shouldReturnToRoot(
            now: now,
            lastBackgroundedAt: nil,
            autoReturnTimeout: .fiveMinutes
        )

        #expect(result == false, "no recorded background timestamp means no trigger")
    }

    @Test("shouldReturnToRoot with future lastBackgroundedAt (clock skew) returns false")
    func shouldReturnToRoot_futureLastBackgroundedAt_returnsFalse() {
        let now = Date()
        let lastBackgroundedAt = Date(timeInterval: 60, since: now)  // 1 minute in the future

        let result = AppDelegate.shouldReturnToRoot(
            now: now,
            lastBackgroundedAt: lastBackgroundedAt,
            autoReturnTimeout: .fiveMinutes
        )

        #expect(result == false, "negative elapsed time should not satisfy >= timeout")
    }
}
