//
//  TransportClassifiableError.swift
//  FlipcashCore
//

import GRPC

/// A `ServerError` whose failure can originate from a gRPC transport condition
/// (request timeout, unavailable channel) rather than a server result code.
/// Conformers route a transient transport status to a non-reportable case so a
/// flaky connection is logged but never surfaced as a code defect in Bugsnag.
public protocol TransportClassifiableError: ServerError {
    /// Classifies a normalized gRPC failure status (`UnaryCall.handle` routes
    /// NIO/gRPC errors through `makeGRPCStatus()` first). Transient conditions
    /// (`GRPCStatus.Code.isTransientNetworkError`) must map to a case with
    /// `isReportable == false`; everything else preserves the reportable
    /// `.unknown`.
    static func from(transportError: GRPCStatus) -> Self
}
