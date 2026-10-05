//
//  ErrorReporting.swift
//  Code
//
//  Created by Dima Bart on 2023-01-18.
//

import Foundation
import Bugsnag
import FlipcashCore

enum ErrorReporting {

    /// The reporting outcome for a classified error: dropped, or sent at a severity.
    nonisolated enum Outcome: Equatable {
        case drop
        case info
        case error
    }

    /// Resolves how a classified error should be reported.
    ///
    /// `.suppressed` (transient transport / network weather) is normally dropped, but
    /// when it reached the user as a hard failure dialog (`userFacing`) it is lifted to
    /// `.info` — a breadcrumb, never `.error`, so it never pages Slack. Only `.suppressed`
    /// is ever lifted: user-caused refusals classify `.info`/`.error`, so a user-caused
    /// failure can never be surfaced by `userFacing`.
    nonisolated static func outcome(for level: ErrorReportingLevel, userFacing: Bool) -> Outcome {
        switch level {
        case .suppressed: userFacing ? .info : .drop
        case .info:       .info
        case .error:      .error
        }
    }

    /// Which logs belong to an event that reached `OnSendError` without `app_logs`.
    nonisolated enum LogSource: Equatable {
        case currentLaunch
        case previousLaunch
        case none
    }

    /// How long after an event the previous launch's log files may still have been written
    /// and the tail still be that event's launch. Past this, a later launch wrote them.
    nonisolated static let previousLaunchTailSlack: TimeInterval = 60

    /// Chooses the logs for an event by when it happened relative to this launch.
    ///
    /// An event from before this launch (a crash sent on relaunch) gets the previous
    /// launch's tail, unless the tail was written well after the event, which means the
    /// report sat unsent through a later launch. Without an event time, unhandled events
    /// are taken to be crashes from the previous launch.
    nonisolated static func logSource(eventTime: Date?, unhandled: Bool, launchDate: Date?, tailLastWrite: Date?) -> LogSource {
        guard let launchDate else { return .currentLaunch }

        let fromPreviousLaunch: Bool
        if let eventTime {
            fromPreviousLaunch = eventTime < launchDate
        } else {
            fromPreviousLaunch = unhandled
        }
        guard fromPreviousLaunch else { return .currentLaunch }

        guard let tailLastWrite else { return .none }
        if let eventTime, tailLastWrite.timeIntervalSince(eventTime) > previousLaunchTailSlack {
            return .none
        }
        return .previousLaunch
    }

    nonisolated private static let logsSection = "app_logs"
    nonisolated private static let recentLogsKey = "recent_logs"

    private static var isEnabled = false

    static func initialize() {
        let config = BugsnagConfiguration.loadConfig()
        config.maxStringValueLength = 50_000
        // A nonisolated function, not a closure: Bugsnag calls it on its upload queue.
        config.addOnSendError(block: attachLogsIfMissing)
        Bugsnag.start(with: config)
        isEnabled = true
    }

    /// Fills `app_logs` on events that did not get it from `capture`, chiefly crashes, and keeps the event.
    ///
    /// Runs at upload time, which for a crash is the next launch. Events from `capture`
    /// already carry the section, stored with the event, so a retried upload keeps the
    /// logs from when it happened.
    nonisolated private static func attachLogsIfMissing(to event: BugsnagEvent) -> Bool {
        guard event.getMetadata(section: logsSection, key: recentLogsKey) == nil else { return true }

        let store = LogStore.shared
        let tail = store.previousLaunchTail
        let source = logSource(
            eventTime: event.device.time,
            unhandled: event.unhandled,
            launchDate: store.launchDate,
            tailLastWrite: tail.lastWrite
        )

        switch source {
        case .currentLaunch:
            event.addMetadata(store.recentEntries(last: 100).joined(separator: "\n"), key: recentLogsKey, section: logsSection)
        case .previousLaunch:
            event.addMetadata(tail.lines.joined(separator: "\n"), key: recentLogsKey, section: logsSection)
            if let lastWrite = tail.lastWrite {
                event.addMetadata(lastWrite.ISO8601Format(), key: "previous_launch_last_write", section: logsSection)
            }
        case .none:
            break
        }
        return true
    }

    static func capturePayment(error: Swift.Error, rendezvous: PublicKey, exchangedFiat: ExchangedFiat, verifiedState: VerifiedState? = nil, reason: String? = nil, userFacing: Bool = false, file: String = #file, function: String = #function, line: Int = #line) {
        capture(error, reason: reason, userFacing: userFacing, file: file, function: function, line: line) { userInfo in
            userInfo["rendezvous"]    = rendezvous.base58
            userInfo["exchangedFiat"] = exchangedFiat.descriptionDictionary
            if let verifiedState {
                userInfo["rateTimestamp"]  = verifiedState.timestamp.description
                userInfo["rateValue"]      = verifiedState.exchangeRate
                userInfo["rateAgeMins"]    = String(format: "%.1f", Date().timeIntervalSince(verifiedState.timestamp) / 60)
                userInfo["hasReserveState"] = verifiedState.reserveProto != nil
                if let supply = verifiedState.supplyFromBonding {
                    userInfo["supplyFromBonding"] = supply
                }
            } else {
                userInfo["verifiedState"] = "nil"
            }
            userInfo["mint"] = exchangedFiat.mint.base58
        }
    }
    
    static func capturePayment(error: Swift.Error, rendezvous: PublicKey, fiat: FiatAmount, reason: String? = nil, userFacing: Bool = false, file: String = #file, function: String = #function, line: Int = #line) {
        capture(error, reason: reason, userFacing: userFacing, file: file, function: function, line: line) { userInfo in
            userInfo["rendezvous"] = rendezvous.base58
            userInfo["usdc"]       = fiat.formatted()
            userInfo["value"]      = "\(fiat.value)"
        }
    }
    
    /// Reports a non-fatal error to Bugsnag with optional context.
    ///
    /// - Parameters:
    ///   - error: The error to report.
    ///   - reason: A human-readable description that becomes the Bugsnag error message
    ///     and `NSLocalizedFailureReasonErrorKey` in the event's user info.
    ///   - id: An optional identifier appended to the grouping hash. Use this when a
    ///     single function contains multiple catch sites that should group separately.
    ///   - metadata: Key-value pairs attached to the Bugsnag event's user info for
    ///     debugging context (e.g. mint, amount, swap ID).
    ///   - userFacing: Pass `true` when this error was surfaced to the user as a hard
    ///     failure dialog. A `.suppressed` (transient transport) error that reached a
    ///     dialog is then recorded at `.info` instead of dropped — a breadcrumb, never
    ///     a Slack page. Has no effect on `.info`/`.error` errors.
    static func captureError(_ error: Swift.Error, reason: String? = nil, id: String? = nil, metadata: [String: String] = [:], userFacing: Bool = false, file: String = #file, function: String = #function, line: Int = #line) {
        capture(error, reason: reason, id: id, userFacing: userFacing, file: file, function: function, line: line) { userInfo in
            metadata.forEach { key, value in
                userInfo[key] = value
            }
        }
    }
    
    private static func capture(_ error: Swift.Error, reason: String? = nil, id: String? = nil, userFacing: Bool = false, file: String = #file, function: String = #function, line: Int = #line, buildUserInfo: (inout [String: Any]) -> Void) {
        guard isEnabled else { return }

        // A non-ServerError reaching the reporter is unclassified — treat as a real bug.
        let level = (error as? ServerError)?.reportingLevel ?? .error
        let severity: BSGSeverity
        switch outcome(for: level, userFacing: userFacing) {
        case .drop:
            return
        case .info:
            severity = .info
        case .error:
            severity = .error
        }

        let swiftError = error as NSError

        var userInfo: [String: Any] = [:]

        swiftError.userInfo.forEach { key, value in
            userInfo[key] = value
        }

        let fileName = file.components(separatedBy: "/").last ?? "unknown"
        let location = "\(fileName):\(function):\(line)"
        userInfo["location"] = location

        buildUserInfo(&userInfo)

        if let reason {
            userInfo[NSLocalizedFailureReasonErrorKey] = reason
        }

        let recentLogs = LogStore.shared.recentEntries(last: 100)

        let customError = Fault(
            domain: "\(swiftError.domain).\(error)",
            code: swiftError.code,
            userInfo: userInfo
        )

        Bugsnag.notifyError(customError) { event in
            event.severity = severity

            if !event.errors.isEmpty {
                event.errors[0].errorClass = reason ?? "\(error)"
                event.errors[0].errorMessage = "\(error)"
            }

            event.addMetadata(
                recentLogs.joined(separator: "\n"),
                key: recentLogsKey,
                section: logsSection
            )

            // Skip the line numbers to maintain grouping
            // even when files and line numbers change.
            var hash = "\(fileName):\(function)"
            if let id {
                hash = "\(hash):\(id)"
            }
            event.groupingHash = hash

            return true
        }
    }
}

nonisolated class Fault: NSError, @unchecked Sendable {}
