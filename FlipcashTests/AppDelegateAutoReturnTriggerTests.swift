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

    @Test(
        "shouldAutoReturn returns expected result for elapsed/timeout matrix",
        arguments: [
            (offset: TimeInterval(-360), timeout: AutoReturnTimeout.fiveMinutes, expected: true,  description: "6m elapsed > 5m timeout"),
            (offset: TimeInterval(-240), timeout: AutoReturnTimeout.fiveMinutes, expected: false, description: "4m elapsed < 5m timeout"),
            (offset: TimeInterval(-300), timeout: AutoReturnTimeout.fiveMinutes, expected: true,  description: "5m elapsed == 5m timeout (>= boundary)"),
            (offset: TimeInterval(-660), timeout: AutoReturnTimeout.tenMinutes,  expected: true,  description: "11m elapsed > 10m timeout"),
            (offset: TimeInterval(-360), timeout: AutoReturnTimeout.never,       expected: false, description: ".never opts out entirely"),
            (offset: TimeInterval(60),   timeout: AutoReturnTimeout.fiveMinutes, expected: false, description: "future timestamp / clock skew"),
        ]
    )
    func shouldAutoReturn_elapsedTimeoutMatrix(
        offset: TimeInterval,
        timeout: AutoReturnTimeout,
        expected: Bool,
        description: String
    ) {
        let now = Date()
        let lastBackgroundedAt = Date(timeInterval: offset, since: now)

        let result = AppDelegate.shouldAutoReturn(
            now: now,
            lastBackgroundedAt: lastBackgroundedAt,
            autoReturnTimeout: timeout
        )

        #expect(result == expected, "\(description)")
    }

    @Test("shouldAutoReturn with nil lastBackgroundedAt returns false")
    func shouldAutoReturn_nilLastBackgroundedAt_returnsFalse() {
        #expect(
            !AppDelegate.shouldAutoReturn(
                now: Date(),
                lastBackgroundedAt: nil,
                autoReturnTimeout: .fiveMinutes
            )
        )
    }
}
