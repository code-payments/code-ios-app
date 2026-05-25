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
