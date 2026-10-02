//
//  StoreWriteGuard.swift
//  FlipcashStore
//

import Foundation
import FlipcashCore

/// Brackets every write to the store so the host can keep the process from being suspended while
/// the write holds a SQLite lock.
///
/// The store lives in an App Group container, and iOS kills a process suspended while holding a
/// lock on a shared file (`0xdead10cc`). `FlipcashStore` cannot see `UIApplication`, so the app
/// injects a guard that holds a background-task assertion; extensions and tests use ``none``.
///
/// Calls nest — a write that runs inside another write's transaction begins again — and may arrive
/// on any thread.
public protocol StoreWriteGuard: Sendable {

    /// Called before a write touches the store. Throws ``StoreWriteRefused`` when the write cannot be
    /// protected, and the write does not start.
    func begin() throws

    /// Balances one successful ``begin()``, after the write has released its lock.
    func end()
}

/// A guard that never refuses and holds nothing.
public struct NoStoreWriteGuard: StoreWriteGuard {

    public init() {}

    public func begin() throws {}

    public func end() {}
}

extension StoreWriteGuard where Self == NoStoreWriteGuard {

    /// For processes that are not suspended under a held lock: extensions and tests.
    public static var none: NoStoreWriteGuard { NoStoreWriteGuard() }
}

/// Thrown by a ``StoreWriteGuard`` when the process is about to be suspended and a write could not
/// finish under protection.
///
/// Expected near every suspension and harmless — the store is rebuilt from the server — so it
/// classifies as suppressed and never reaches error reporting.
public struct StoreWriteRefused: ServerError, Equatable {

    public var reportingLevel: ErrorReportingLevel { .suppressed }

    public init() {}
}
