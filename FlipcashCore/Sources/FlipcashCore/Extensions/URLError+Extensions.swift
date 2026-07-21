//
//  URLError+Extensions.swift
//  FlipcashCore
//

import Foundation

extension URLError.Code {

    /// Whether the code represents a transient network condition — the URL
    /// loading system's counterpart to `RPCError.Code.isTransientNetworkError`.
    /// Excludes server-side and payload failures, which stay visible.
    public var isTransientNetworkError: Bool {
        switch self {
        case .timedOut, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost,
             .notConnectedToInternet, .dnsLookupFailed, .internationalRoamingOff,
             .callIsActive, .dataNotAllowed, .resourceUnavailable:
            true
        default:
            false
        }
    }
}

extension URLError: ServerError {

    /// Transient transport conditions are suppressed; `.cancelled` is
    /// app-initiated teardown so it stays visible at `.info`; every other code
    /// is an unexpected state and reports at `.error`. This lets plain-HTTP
    /// legs ship the error directly — wrapped in a domain error's `.network`
    /// case or not — and still classify correctly.
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
