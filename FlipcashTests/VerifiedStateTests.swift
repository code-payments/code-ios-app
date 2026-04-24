//
//  VerifiedStateTests.swift
//  FlipcashTests
//

import Testing
import Foundation
@testable import Flipcash
import FlipcashCore

@Suite("VerifiedState")
struct VerifiedStateTests {

    struct TimestampCase: Sendable, CustomTestStringConvertible {
        let name: String
        let rate: Date
        let reserve: Date?
        let expected: Date
        var testDescription: String { name }
    }

    @Test(
        "serverTimestamp uses the oldest available proof timestamp",
        arguments: [
            TimestampCase(
                name: "reserve is older than rate → uses reserve",
                rate: Date(timeIntervalSince1970: 1_000),
                reserve: Date(timeIntervalSince1970: 500),
                expected: Date(timeIntervalSince1970: 500)
            ),
            TimestampCase(
                name: "rate is older than reserve → uses rate",
                rate: Date(timeIntervalSince1970: 500),
                reserve: Date(timeIntervalSince1970: 1_000),
                expected: Date(timeIntervalSince1970: 500)
            ),
            TimestampCase(
                name: "reserve absent → falls back to rate",
                rate: Date(timeIntervalSince1970: 1_000),
                reserve: nil,
                expected: Date(timeIntervalSince1970: 1_000)
            ),
        ]
    )
    func serverTimestamp_picksOldestAvailable(scenario: TimestampCase) {
        let state = VerifiedState.makeForTest(
            rateTimestamp: scenario.rate,
            reserveTimestamp: scenario.reserve
        )
        #expect(state.serverTimestamp == scenario.expected)
    }

    struct StaleCase: Sendable, CustomTestStringConvertible {
        let name: String
        let offsetFromNow: TimeInterval
        let expected: Bool
        var testDescription: String { name }
    }

    @Test(
        "isStale boundary at clientMaxAge",
        arguments: [
            StaleCase(name: "brand new proof", offsetFromNow: 0, expected: false),
            StaleCase(name: "1 minute under the cutoff", offsetFromNow: -(VerifiedState.clientMaxAge - 60), expected: false),
            StaleCase(name: "1 second past the cutoff", offsetFromNow: -(VerifiedState.clientMaxAge + 1), expected: true),
            StaleCase(name: "5 minutes past the cutoff", offsetFromNow: -(VerifiedState.clientMaxAge + 5 * 60), expected: true),
        ]
    )
    func isStale_respectsBoundary(scenario: StaleCase) {
        let state = VerifiedState.makeForTest(
            rateTimestamp: Date().addingTimeInterval(scenario.offsetFromNow),
            reserveTimestamp: nil
        )
        #expect(state.isStale == scenario.expected)
    }

    @Test("clientMaxAge equals 13 minutes")
    func clientMaxAge_value() {
        #expect(VerifiedState.clientMaxAge == 13 * 60)
    }
}
