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

/// Collects what the Analytics overrides receive while a recording is bound.
@MainActor
private final class AnalyticsRecorder {
    var sent: [SentEvent] = []
    var increments: [(property: String, amount: Double)] = []
}

@MainActor
extension Analytics {
    /// Runs `body` with Mixpanel replaced by a recorder and returns every event it sent.
    /// The hook is task-local: only events sent from `body`'s task and its child tasks are
    /// recorded, so tests running in parallel can't leak into each other's recordings.
    static func recordingSends(_ body: () -> Void) -> [SentEvent] {
        let recorder = AnalyticsRecorder()
        $sendOverride.withValue({ name, properties in
            recorder.sent.append(SentEvent(name: name, properties: properties))
        }) {
            body()
        }
        return recorder.sent
    }

    /// `recordingSends` for a body that awaits, such as a model's async save.
    static func recordingSendsAsync(_ body: () async -> Void) async -> [SentEvent] {
        let recorder = AnalyticsRecorder()
        await $sendOverride.withValue({ name, properties in
            recorder.sent.append(SentEvent(name: name, properties: properties))
        }) {
            await body()
        }
        return recorder.sent
    }

    /// Runs `body` with the Mixpanel people increment replaced by a recorder and returns
    /// every increment it made, as property name and amount.
    static func recordingIncrements(_ body: () -> Void) -> [(property: String, amount: Double)] {
        let recorder = AnalyticsRecorder()
        $incrementOverride.withValue({ property, amount in
            recorder.increments.append((property, amount))
        }) {
            body()
        }
        return recorder.increments
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
