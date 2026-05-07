//
//  ServerError.swift
//  FlipcashCore
//

import Foundation

/// Marker for errors carrying a server-returned result code (denied, not-found,
/// invalid-input, etc.). Filtered out of error reporting by default — they
/// represent user-driven outcomes, not iOS bugs.
///
/// Override `isReportable` per enum to surface specific cases that *should*
/// reach the reporter — typically `.unknown` (raw value the client doesn't
/// recognize → proto/client drift) and wrapped non-business causes.
public protocol ServerError: Error {
    var isReportable: Bool { get }
}

public extension ServerError {
    var isReportable: Bool { false }
}
