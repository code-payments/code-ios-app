//
//  TransportClassifiableError.swift
//  FlipcashCore
//

import GRPCCore
import Logging

private let logger = Logger(label: "flipcash.transport-error")

/// A `ServerError` whose failure can originate from a gRPC transport condition
/// (request timeout, cancellation, unavailable channel) rather than a server
/// result code. Classification is decided in exactly one place —
/// `RPCError.reportingLevel` plus `RPCError.Code.isDeterministicRejection` —
/// and `from(transportError:)` projects that verdict onto the conformer's four
/// transport cases: `.transportFailure` (suppressed), `.cancelled` (info),
/// `.rejected` (error; the server definitively refused, retry can never help),
/// and `.unknown` (error; unclassified anomaly, retry may help). Conformers
/// declare the four cases; they never re-classify. The `.rejected` and
/// `.unknown` outcomes log the underlying error, since the case alone
/// can't say why the call failed.
public protocol TransportClassifiableError: ServerError {
    static var transportFailure: Self { get }
    static var cancelled: Self { get }
    static var rejected: Self { get }
    static var unknown: Self { get }
}

public extension TransportClassifiableError {
    static func from(transportError error: RPCError) -> Self {
        switch error.reportingLevel {
        case .suppressed:
            return .transportFailure
        case .info:
            return .cancelled
        case .error:
            let rejected = error.code.isDeterministicRejection
            logger.warning("RPC failed", metadata: [
                "type": "\(Self.self)",
                "outcome": "\(rejected ? "rejected" : "unknown")",
                "code": "\(error.code)",
                "message": "\(error.message)",
            ])
            return rejected ? .rejected : .unknown
        }
    }

    /// Maps an error that isn't an `RPCError` to `.unknown`, logging its type
    /// and description.
    static func from(unexpectedError error: any Error) -> Self {
        logger.warning("Unexpected error", metadata: [
            "type": "\(Self.self)",
            "errorType": "\(type(of: error))",
            "error": "\(error)",
        ])
        return .unknown
    }
}

public extension TransportClassifiableError where Self: Equatable {
    /// Whether a failed call is worth another attempt: transient transport
    /// failures and unclassified anomalies retry; deterministic rejections,
    /// explicit server outcomes, and cancellation do not. Call sites compose
    /// their own additions (e.g. `e == .notFound || e.isRetryable`).
    var isRetryable: Bool { self == .unknown || self == .transportFailure }
}
