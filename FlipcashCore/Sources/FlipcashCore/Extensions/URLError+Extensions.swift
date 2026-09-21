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
        } else if code == .secureConnectionFailed, isTLSConnectionDrop {
            .suppressed
        } else if code == .cancelled {
            .info
        } else {
            .error
        }
    }

    /// Whether a `.secureConnectionFailed` was a TLS session severed in flight
    /// rather than one refused on trust grounds.
    ///
    /// `-1200` is only an envelope: a dropped connection and an expired or
    /// invalid certificate chain arrive under the same code, so suppressing on
    /// the envelope alone would mute a genuine trust signal. The real cause is
    /// the underlying Secure Transport code, which is why this check cannot
    /// live on `URLError.Code` — that type is built from a bare `Int` and never
    /// sees `userInfo`. Anything unrecognized, including an absent key, stays
    /// reportable.
    private var isTLSConnectionDrop: Bool {
        // `_kCFStreamErrorCodeKey` is CFNetwork SPI — Apple has never committed
        // to it, so its absence has to be survivable rather than assumed.
        guard let streamCode = (self as NSError).userInfo["_kCFStreamErrorCodeKey"] as? Int else {
            return false
        }
        // <Security/SecBase.h>: errSSLClosedAbort ("connection closed via
        // error") and errSSLClosedNoNotify ("server closed session with no
        // notification"). Both mean the peer went away mid-exchange.
        return streamCode == -9806 || streamCode == -9816
    }
}
