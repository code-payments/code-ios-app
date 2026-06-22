//
//  ReconnectBackoffTests.swift
//  FlipcashTests
//

import Foundation
import Testing
@testable import FlipcashCore

@Suite("ReconnectBackoff")
struct ReconnectBackoffTests {

    // MARK: - next -

    @Test("next doubles each attempt, then caps at the maximum")
    func next_doublesThenCaps() {
        var backoff = ReconnectBackoff()
        // Doubles per attempt — then capped at 30 once 2^n would exceed it.
        let expected: [TimeInterval] = [1, 2, 4, 8, 16, 30, 30, 30]
        for delay in expected {
            #expect(backoff.next() == delay)
        }
    }

    // MARK: - reset -

    @Test("Reset returns the delay to the base after consecutive failures")
    func reset_returnsToBase() {
        var backoff = ReconnectBackoff()
        _ = backoff.next() // 1
        _ = backoff.next() // 2
        _ = backoff.next() // 4
        #expect(backoff.attempts == 3)

        backoff.reset()

        #expect(backoff.attempts == 0)
        #expect(backoff.next() == 1)
    }
}
