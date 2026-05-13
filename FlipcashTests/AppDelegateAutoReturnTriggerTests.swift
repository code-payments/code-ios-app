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

    @Test(
        "consumeAutoReturn matrix",
        arguments: [
            (offset: TimeInterval?(-360), consumes: true,  endsAsNil: true,  description: "6m elapsed > 5m timeout consumes and clears"),
            (offset: TimeInterval?(-300), consumes: true,  endsAsNil: true,  description: "5m elapsed == 5m timeout (>= boundary) consumes"),
            (offset: TimeInterval?(-240), consumes: false, endsAsNil: false, description: "4m elapsed < 5m timeout no-op, preserves timestamp"),
            (offset: TimeInterval?(60),   consumes: false, endsAsNil: false, description: "future timestamp / clock skew preserves"),
            (offset: TimeInterval?.none,  consumes: false, endsAsNil: true,  description: "nil input stays nil, returns false"),
        ]
    )
    func consumeAutoReturn_matrix(
        offset: TimeInterval?,
        consumes: Bool,
        endsAsNil: Bool,
        description: String
    ) {
        let now = Date()
        let original: Date? = offset.map { Date(timeInterval: $0, since: now) }
        var lastBackgroundedAt: Date? = original

        let result = AppDelegate.consumeAutoReturn(
            now: now,
            lastBackgroundedAt: &lastBackgroundedAt
        )

        #expect(result == consumes, "\(description) — return value")
        let expectedAfter: Date? = endsAsNil ? nil : original
        #expect(lastBackgroundedAt == expectedAfter, "\(description) — final timestamp")
    }

    @Test("consumeAutoReturn is one-shot — second call after consuming returns false")
    func consumeAutoReturn_secondCall_returnsFalse() throws {
        let now = Date()
        var lastBackgroundedAt: Date? = Date(timeInterval: -360, since: now)

        // Precondition: first call consumes the gate. If this fails, the
        // one-shot assertion below is meaningless.
        try #require(AppDelegate.consumeAutoReturn(
            now: now,
            lastBackgroundedAt: &lastBackgroundedAt
        ))

        let didConsumeAgain = AppDelegate.consumeAutoReturn(
            now: now,
            lastBackgroundedAt: &lastBackgroundedAt
        )

        #expect(didConsumeAgain == false)
        #expect(lastBackgroundedAt == nil)
    }
}
