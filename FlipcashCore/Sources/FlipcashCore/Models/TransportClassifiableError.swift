//
//  TransportClassifiableError.swift
//  FlipcashCore
//

import GRPCCore

/// A `ServerError` whose failure can originate from a gRPC transport condition
/// (request timeout, unavailable channel) rather than a server result code.
/// The classification lives here once: a transient `RPCError` (per
/// `RPCError.Code.isTransientNetworkError`) becomes `.transportFailure` — which
/// the conformer must mark non-reportable — and anything else stays `.unknown`.
/// Conformers just declare conformance; their `.transportFailure` and `.unknown`
/// cases satisfy these requirements.
public protocol TransportClassifiableError: ServerError {
    static var transportFailure: Self { get }
    static var unknown: Self { get }
}

public extension TransportClassifiableError {
    static func from(transportError error: RPCError) -> Self {
        error.code.isTransientNetworkError ? .transportFailure : .unknown
    }
}
