//
//  MockContactSync.swift
//  FlipcashTests
//
//  Scriptable in-memory conformer for `ContactSyncing`. Records every RPC
//  call and lets each test pre-load the responses the controller's state
//  machine should observe.
//

import Foundation
import FlipcashCore
@testable import Flipcash

final class MockContactSync: ContactSyncing, @unchecked Sendable {

    // MARK: - Recorded calls -

    struct DeltaCall: Equatable, Sendable {
        let adds: [String]
        let removes: [String]
        let oldChecksum: Data
        let newChecksum: Data
    }

    struct FullCall: Equatable, Sendable {
        let phones: [String]
        let checksum: Data
    }

    /// Serializes mutations to the recorded-call buffers — runSync may invoke
    /// these from a `@concurrent nonisolated` context, while tests read from
    /// `@MainActor`.
    private let lock = NSLock()

    private var _checkSyncCalls: [Data] = []
    private var _deltaCalls:     [DeltaCall] = []
    private var _fullCalls:      [FullCall] = []
    private var _streamCalls:    [Data] = []

    var checkSyncCalls: [Data]    { lock.withLock { _checkSyncCalls } }
    var deltaCalls:     [DeltaCall] { lock.withLock { _deltaCalls } }
    var fullCalls:      [FullCall]  { lock.withLock { _fullCalls } }
    var streamCalls:    [Data]    { lock.withLock { _streamCalls } }

    // MARK: - Scripted responses -

    var checkSyncResult:    Result<CheckSyncResult, Error>   = .success(.ok)
    var deltaUploadResult:  Result<DeltaUploadResult, Error> = .success(.ok)
    var fullUploadResult:   Result<Void, Error>              = .success(())
    var streamYields:       [String] = []
    var streamTerminalError: Error?

    // MARK: - ContactSyncing -

    func checkContactSync(checksum: Data, owner: KeyPair) async throws -> CheckSyncResult {
        lock.withLock { _checkSyncCalls.append(checksum) }
        return try checkSyncResult.get()
    }

    func uploadContactDelta(
        adds: [String],
        removes: [String],
        oldChecksum: Data,
        newChecksum: Data,
        owner: KeyPair
    ) async throws -> DeltaUploadResult {
        lock.withLock {
            _deltaCalls.append(DeltaCall(
                adds:        adds,
                removes:     removes,
                oldChecksum: oldChecksum,
                newChecksum: newChecksum
            ))
        }
        return try deltaUploadResult.get()
    }

    func uploadAllContacts(phones: [String], checksum: Data, owner: KeyPair) async throws {
        lock.withLock {
            _fullCalls.append(FullCall(phones: phones, checksum: checksum))
        }
        try fullUploadResult.get()
    }

    func streamFlipcashContacts(checksum: Data, owner: KeyPair) -> AsyncThrowingStream<String, Error> {
        lock.withLock { _streamCalls.append(checksum) }
        let yields = streamYields
        let error  = streamTerminalError
        return AsyncThrowingStream { continuation in
            for value in yields {
                continuation.yield(value)
            }
            if let error {
                continuation.finish(throwing: error)
            } else {
                continuation.finish()
            }
        }
    }
}
