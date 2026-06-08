//
//  GRPCStatus+Extensions.swift
//  FlipcashCore
//

import GRPC

extension GRPCStatus.Code {

    /// Whether the code represents a transient network condition (deadline
    /// expired or channel unavailable). Excludes `.cancelled`, `.aborted`,
    /// and `.unknown` by design — those stay reportable so app cancellations
    /// and server aborts remain visible in error tracking.
    public var isTransientNetworkError: Bool {
        switch self {
        case .deadlineExceeded, .unavailable: true
        default: false
        }
    }
}

extension GRPCStatus: ServerError {

    /// A raw transport status is non-reportable only for transient network
    /// conditions (`GRPCStatus.Code.isTransientNetworkError`); every other code
    /// stays reportable. This lets unary RPCs whose failure type is the
    /// existential `Error` ship the status directly and still classify
    /// correctly, without a dedicated `TransportClassifiableError` enum.
    public var isReportable: Bool {
        !code.isTransientNetworkError
    }
}
