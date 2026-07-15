//
//  TransportClassifiableError.swift
//  FlipcashCore
//

import GRPCCore

/// A `ServerError` whose failure can originate from a gRPC transport condition
/// (request timeout, cancellation, unavailable channel) rather than a server
/// result code. Severity is decided in exactly one place — `RPCError.reportingLevel`
/// — and `from(transportError:)` projects that verdict onto the conformer's three
/// transport cases: `.transportFailure` (suppressed), `.cancelled` (info), and
/// `.unknown` (error). Conformers declare the three cases; they never re-classify.
public protocol TransportClassifiableError: ServerError {
    static var transportFailure: Self { get }
    static var cancelled: Self { get }
    static var unknown: Self { get }
}

public extension TransportClassifiableError {
    static func from(transportError error: RPCError) -> Self {
        switch error.reportingLevel {
        case .suppressed: .transportFailure
        case .info:       .cancelled
        case .error:      .unknown
        }
    }
}

public extension TransportClassifiableError where Self: Equatable {
    /// Whether a failed call is worth another attempt: transient transport
    /// failures and unclassified errors retry; explicit server outcomes and
    /// cancellation do not. Call sites compose their own additions
    /// (e.g. `e == .notFound || e.isRetryable`).
    var isRetryable: Bool { self == .unknown || self == .transportFailure }
}
