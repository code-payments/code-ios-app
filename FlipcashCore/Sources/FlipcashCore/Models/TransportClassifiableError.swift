//
//  TransportClassifiableError.swift
//  FlipcashCore
//

import GRPC

/// A `ServerError` whose failure can originate from a gRPC transport condition
/// (request timeout, unavailable channel) rather than a server result code.
/// The classification lives here once: a transient status (per
/// `GRPCStatus.Code.isTransientNetworkError`) becomes `.transportFailure` —
/// which the conformer must mark non-reportable — and anything else stays
/// `.unknown`. Conformers just declare conformance; their `.transportFailure`
/// and `.unknown` cases satisfy these requirements.
public protocol TransportClassifiableError: ServerError {
    static var transportFailure: Self { get }
    static var unknown: Self { get }
}

public extension TransportClassifiableError {
    static func from(transportError status: GRPCStatus) -> Self {
        status.code.isTransientNetworkError ? .transportFailure : .unknown
    }
}
