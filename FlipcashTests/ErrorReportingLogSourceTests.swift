//
//  ErrorReportingLogSourceTests.swift
//  Flipcash
//
//  Covers which logs `OnSendError` attaches to an event without `app_logs`: a crash
//  sent on relaunch gets the previous launch's file tail, an in-session event gets the
//  ring buffer, and a tail written by a later launch is not attached.
//

import Foundation
import Testing
@testable import Flipcash

@Suite("ErrorReporting.logSource")
struct ErrorReportingLogSourceTests {

    private let launch = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("An event during this launch gets the ring buffer")
    func inSession() {
        let source = ErrorReporting.logSource(
            eventTime: launch.addingTimeInterval(30),
            unhandled: true,
            launchDate: launch,
            tailLastWrite: launch.addingTimeInterval(-600)
        )
        #expect(source == .currentLaunch)
    }

    @Test("A crash from the previous launch gets the previous launch's tail")
    func crashOnRelaunch() {
        let crash = launch.addingTimeInterval(-120)
        let source = ErrorReporting.logSource(
            eventTime: crash,
            unhandled: true,
            launchDate: launch,
            tailLastWrite: crash.addingTimeInterval(-2)
        )
        #expect(source == .previousLaunch)
    }

    @Test("A tail written shortly after the event still belongs to it")
    func tailWithinSlack() {
        let crash = launch.addingTimeInterval(-120)
        let source = ErrorReporting.logSource(
            eventTime: crash,
            unhandled: true,
            launchDate: launch,
            tailLastWrite: crash.addingTimeInterval(ErrorReporting.previousLaunchTailSlack)
        )
        #expect(source == .previousLaunch)
    }

    @Test("A tail written by a later launch is not attached")
    func staleReport() {
        let crash = launch.addingTimeInterval(-86_400)
        let source = ErrorReporting.logSource(
            eventTime: crash,
            unhandled: true,
            launchDate: launch,
            tailLastWrite: launch.addingTimeInterval(-600)
        )
        #expect(source == .none)
    }

    @Test("An event from before this launch with no log files gets nothing")
    func noTail() {
        let source = ErrorReporting.logSource(
            eventTime: launch.addingTimeInterval(-120),
            unhandled: true,
            launchDate: launch,
            tailLastWrite: nil
        )
        #expect(source == .none)
    }

    @Test("Without an event time, unhandled means the previous launch", arguments: [
        (true, ErrorReporting.LogSource.previousLaunch),
        (false, .currentLaunch),
    ])
    func noEventTime(unhandled: Bool, expected: ErrorReporting.LogSource) {
        let source = ErrorReporting.logSource(
            eventTime: nil,
            unhandled: unhandled,
            launchDate: launch,
            tailLastWrite: launch.addingTimeInterval(-600)
        )
        #expect(source == expected)
    }

    @Test("Before LogStore.bootstrap records a launch, the ring buffer is used")
    func noLaunchDate() {
        let source = ErrorReporting.logSource(
            eventTime: launch,
            unhandled: true,
            launchDate: nil,
            tailLastWrite: launch
        )
        #expect(source == .currentLaunch)
    }
}
