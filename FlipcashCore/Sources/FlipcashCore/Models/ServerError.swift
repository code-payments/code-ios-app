//
//  ServerError.swift
//  FlipcashCore
//

import Foundation

/// How an error should surface in error reporting.
public enum ErrorReportingLevel: Sendable, Equatable {
    /// Never sent. Network weather (transport failures) and success sentinels.
    case suppressed
    /// Sent at info severity. Expected, user-driven server outcomes (denied,
    /// not-found, rate-limited) — visible for triage but not a defect.
    case info
    /// Sent at error severity. Client/proto defects: unrecognized codes,
    /// parse failures, signature errors.
    case error
}

/// Marker for errors carrying a server-returned result code (denied, not-found,
/// invalid-input, etc.) or an otherwise classifiable failure.
///
/// There is deliberately no default implementation: every conformer must place
/// each case explicitly — `.suppressed` for network weather / success sentinels,
/// `.info` for expected business outcomes, `.error` for client/proto defects
/// (typically `.unknown`). A defaulted level would let a forgotten or drifted
/// conformance compile while silently muting its errors.
public protocol ServerError: Error {
    var reportingLevel: ErrorReportingLevel { get }
}

/// The reporting outcome for a classified error: dropped, or sent at a severity.
public enum ReportingOutcome: Sendable, Equatable {
    case drop
    case info
    case error

    /// Resolves how a classified error should be reported.
    ///
    /// `.suppressed` (transient transport / network weather) is normally dropped, but
    /// when it reached the user as a hard failure dialog (`userFacing`) it is lifted to
    /// `.info` — a breadcrumb, never `.error`. Only `.suppressed` is ever lifted.
    public static func resolve(level: ErrorReportingLevel, userFacing: Bool) -> ReportingOutcome {
        switch level {
        case .suppressed: userFacing ? .info : .drop
        case .info:       .info
        case .error:      .error
        }
    }

    /// Resolves an arbitrary error: `CancellationError` is dropped (a cancelled task
    /// is not a defect), a `ServerError` uses its `reportingLevel`, and anything
    /// unclassified is a real bug and reports at `.error`.
    public static func resolve(error: Error, userFacing: Bool = false) -> ReportingOutcome {
        if error is CancellationError { return .drop }
        let level = (error as? ServerError)?.reportingLevel ?? .error
        return resolve(level: level, userFacing: userFacing)
    }
}
