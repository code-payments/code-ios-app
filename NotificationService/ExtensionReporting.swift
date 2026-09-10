//
//  ExtensionReporting.swift
//  NotificationService
//

import Foundation
import Bugsnag

/// Crash and error reporting for the notification service extension process.
///
/// Deliberately separate from the app's `ErrorReporting`: that type lives in the
/// app target, and hoisting it into `FlipcashCore` would make the whole core
/// package — including the macOS vector test plans — depend on Bugsnag.
///
/// Note what this cannot see. A jetsam kill for exceeding the extension's memory
/// limit terminates the process without an exception, so it produces no report.
/// Memory headroom has to be measured, not inferred from silence here.
enum ExtensionReporting {

    private static let lock = NSLock()
    // Guarded by `lock`, not by isolation — the extension calls this from ordinary
    // dispatch queues, not actors, so a lock is the synchronization mechanism here.
    private static nonisolated(unsafe) var _isStarted = false

    private static var isStarted: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isStarted
    }

    /// Starts Bugsnag once per extension process. Safe to call on every push:
    /// the extension is torn down and relaunched often, and each new process
    /// needs its own start.
    static func startIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        guard !_isStarted else { return }

        let config = BugsnagConfiguration.loadConfig()
        config.maxStringValueLength = 50_000
        // Distinguishes extension events from the app's in the Bugsnag dashboard;
        // without it both processes report under the same app id and the NSE's
        // crashes are indistinguishable from the app's.
        config.addMetadata("notification-service", key: "process", section: "app")
        Bugsnag.start(with: config)
        _isStarted = true
    }

    /// Reports a non-fatal from the extension. No-op before `startIfNeeded`.
    static func capture(_ error: Swift.Error, reason: String, metadata: [String: String] = [:]) {
        guard isStarted else { return }
        Bugsnag.notifyError(error as NSError) { event in
            event.severity = .error
            if !event.errors.isEmpty {
                event.errors[0].errorClass = reason
                event.errors[0].errorMessage = "\(error)"
            }
            metadata.forEach { key, value in
                event.addMetadata(value, key: key, section: "extension")
            }
            event.groupingHash = reason
            return true
        }
    }

    /// Records a named checkpoint so a later crash report shows how far the
    /// extension got. A `0xdead10cc` termination arrives with no Swift error
    /// attached, so the breadcrumb trail is the only evidence of where the
    /// process was when it died.
    static func breadcrumb(_ message: String, metadata: [String: String] = [:]) {
        guard isStarted else { return }
        Bugsnag.leaveBreadcrumb(message, metadata: metadata, type: .process)
    }
}
