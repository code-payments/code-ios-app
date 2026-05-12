//
//  AppDelegateAutoReturnTriggerTests.swift
//  FlipcashTests
//
//  Created by Raul Riera on 2026-05-08.
//

import Foundation
import Testing
@testable import Flipcash

@Suite("AppDelegate Auto-Return Trigger")
struct AppDelegateAutoReturnTriggerTests {

    @Test(
        "shouldAutoReturn returns expected result for elapsed-time matrix",
        arguments: [
            (offset: TimeInterval(-360), expected: true,  description: "6m elapsed > 5m timeout"),
            (offset: TimeInterval(-240), expected: false, description: "4m elapsed < 5m timeout"),
            (offset: TimeInterval(-300), expected: true,  description: "5m elapsed == 5m timeout (>= boundary)"),
            (offset: TimeInterval(60),   expected: false, description: "future timestamp / clock skew"),
        ]
    )
    func shouldAutoReturn_elapsedMatrix(
        offset: TimeInterval,
        expected: Bool,
        description: String
    ) {
        let now = Date()
        let lastBackgroundedAt = Date(timeInterval: offset, since: now)

        let result = AppDelegate.shouldAutoReturn(
            now: now,
            lastBackgroundedAt: lastBackgroundedAt
        )

        #expect(result == expected, "\(description)")
    }

    @Test("shouldAutoReturn with nil lastBackgroundedAt returns false")
    func shouldAutoReturn_nilLastBackgroundedAt_returnsFalse() {
        #expect(
            !AppDelegate.shouldAutoReturn(
                now: Date(),
                lastBackgroundedAt: nil
            )
        )
    }

    @Test("autoReturnAfter is five minutes")
    func autoReturnAfter_isFiveMinutes() {
        #expect(AppDelegate.autoReturnAfter == 5 * 60)
    }
}
