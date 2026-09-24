//
//  Analytics+TestSupport.swift
//  FlipcashTests
//

import Foundation
import Testing
@testable import Flipcash

/// One event as it would have reached Mixpanel.
struct SentEvent {
    let name: String
    let properties: [String: AnalyticsValue]
}

extension Analytics {
    /// Runs `body` with Mixpanel replaced by a recorder and returns every event it sent.
    /// Suites that call this must be `.serialized`: the hook is process-wide.
    static func recordingSends(_ body: () -> Void) -> [SentEvent] {
        var sent: [SentEvent] = []
        sendOverride = { name, properties in sent.append(SentEvent(name: name, properties: properties)) }
        defer { sendOverride = nil }
        body()
        return sent
    }

    /// Runs `body` with the Mixpanel people increment replaced by a recorder and returns
    /// every increment it made, as property name and amount.
    static func recordingIncrements(_ body: () -> Void) -> [(property: String, amount: Double)] {
        var increments: [(property: String, amount: Double)] = []
        incrementOverride = { property, amount in increments.append((property, amount)) }
        defer { incrementOverride = nil }
        body()
        return increments
    }
}

extension Array where Element == SentEvent {
    /// The one event sent, failing the test when there was not exactly one.
    var single: SentEvent {
        get throws {
            try #require(count == 1, "Expected one event, got \(map(\.name))")
            return self[0]
        }
    }
}
