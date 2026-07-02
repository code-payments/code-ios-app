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
