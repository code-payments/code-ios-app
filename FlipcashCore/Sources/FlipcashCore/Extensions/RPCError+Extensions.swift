//
//  RPCError+Extensions.swift
//  FlipcashCore
//

import GRPCCore

extension RPCError.Code {

    /// Whether the code represents a transient network condition (deadline
    /// expired or channel unavailable). Excludes `.cancelled`, `.aborted`,
    /// and `.unknown` by design — those stay reportable so app cancellations
    /// and server aborts remain visible in error tracking. Mirrors the v1
    /// `GRPCStatus.Code.isTransientNetworkError` semantics exactly.
    public var isTransientNetworkError: Bool {
        self == .deadlineExceeded || self == .unavailable
    }
}

extension RPCError: ServerError {

    /// A raw transport error is non-reportable only for transient network
    /// conditions (`RPCError.Code.isTransientNetworkError`); every other code
    /// stays reportable. This lets unary RPCs whose failure type is the
    /// existential `Error` ship the error directly and still classify
    /// correctly, without a dedicated `TransportClassifiableError` enum.
    public var isReportable: Bool {
        !code.isTransientNetworkError
    }
}
