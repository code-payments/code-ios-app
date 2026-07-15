//
//  RPCError+Extensions.swift
//  FlipcashCore
//

import GRPCCore

extension RPCError.Code {

    /// Whether the code represents a transient network condition (deadline
    /// expired or channel unavailable). Excludes `.cancelled`, `.aborted`,
    /// and `.unknown` by design — those stay visible in error tracking
    /// (`.cancelled` at `.info` since it's app-initiated teardown, the rest
    /// at `.error`). Mirrors the v1 `GRPCStatus.Code.isTransientNetworkError`
    /// semantics exactly.
    public var isTransientNetworkError: Bool {
        self == .deadlineExceeded || self == .unavailable
    }

    /// Whether the server understood the request and definitively refused it,
    /// so retrying the identical call can never succeed. Excludes anomaly codes
    /// (`.internalError`, `.unknown`, `.dataLoss`), contention (`.aborted`), and
    /// rate limiting (`.resourceExhausted`) — those may clear on retry.
    public var isDeterministicRejection: Bool {
        switch self {
        case .invalidArgument, .notFound, .alreadyExists, .permissionDenied,
             .failedPrecondition, .outOfRange, .unimplemented, .unauthenticated:
            true
        default:
            false
        }
    }
}

extension RPCError: ServerError {

    /// Transient transport conditions (`RPCError.Code.isTransientNetworkError`)
    /// are suppressed; `.cancelled` is app/user-initiated teardown (a dismissed
    /// screen cancelling its in-flight call) so it stays visible at `.info`;
    /// every other code is an unexpected transport/server state and reports at
    /// `.error`. This lets unary RPCs whose failure type is the existential
    /// `Error` ship the error directly and still classify correctly, without a
    /// dedicated `TransportClassifiableError` enum.
    public var reportingLevel: ErrorReportingLevel {
        if code.isTransientNetworkError {
            .suppressed
        } else if code == .cancelled {
            .info
        } else {
            .error
        }
    }
}
