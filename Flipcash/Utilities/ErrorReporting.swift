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
    
    static func initialize() {
        let config = BugsnagConfiguration.loadConfig()
        config.maxStringValueLength = 50_000
        Bugsnag.start(with: config)
    }
    
    static func breadcrumb(_ breadcrumb: Breadcrumb) {
        Bugsnag.leaveBreadcrumb(
            breadcrumb.rawValue,
            metadata: nil,
            type: .navigation
        )
    }
    
    enum BreadcrumbType {
        case user
        case process
        case request
        
        var value: BSGBreadcrumbType {
            switch self {
            case .user:    return .user
            case .process: return .process
            case .request: return .request
            }
        }
    }
    
    static func breadcrumb(name: String, metadata: [String: Any] = [:], exchangedFiat: ExchangedFiat? = nil, fiat: FiatAmount? = nil, type: BreadcrumbType) {
        var container: [String: Any] = [:]
        
        metadata.forEach { key, value in
            container[key] = value
        }
        
        if let exchangedFiat {
            container["exchangedFiat"] = exchangedFiat.descriptionDictionary
        }
        
        if let fiat {
            container["fiat"] = fiat.formatted()
        }
        
        Bugsnag.leaveBreadcrumb(
            name,
            metadata: container,
            type: type.value
        )
    }
    
    static func capturePayment(error: Swift.Error, rendezvous: PublicKey, exchangedFiat: ExchangedFiat, verifiedState: VerifiedState? = nil, reason: String? = nil, file: String = #file, function: String = #function, line: Int = #line) {
        capture(error, reason: reason, file: file, function: function, line: line) { userInfo in
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
    
    static func capturePayment(error: Swift.Error, rendezvous: PublicKey, fiat: FiatAmount, reason: String? = nil, file: String = #file, function: String = #function, line: Int = #line) {
        capture(error, reason: reason, file: file, function: function, line: line) { userInfo in
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
    static func captureError(_ error: Swift.Error, reason: String? = nil, id: String? = nil, metadata: [String: String] = [:], file: String = #file, function: String = #function, line: Int = #line) {
        capture(error, reason: reason, id: id, file: file, function: function, line: line) { userInfo in
            metadata.forEach { key, value in
                userInfo[key] = value
            }
        }
    }
    
    private static func capture(_ error: Swift.Error, reason: String? = nil, id: String? = nil, file: String = #file, function: String = #function, line: Int = #line, buildUserInfo: (inout [String: Any]) -> Void) {
        if let serverError = error as? ServerError, !serverError.isReportable {
            return
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
            if !event.errors.isEmpty {
                event.errors[0].errorClass = reason ?? "\(error)"
                event.errors[0].errorMessage = "\(error)"
            }

            event.addMetadata(
                recentLogs.joined(separator: "\n"),
                key: "recent_logs",
                section: "app_logs"
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

enum Breadcrumb: String {
    case placeholder = "Placeholder"
}
