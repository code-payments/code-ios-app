//
//  MockContactSync.swift
//  FlipcashTests
//

import Foundation
import FlipcashCore
@testable import Flipcash

/// Scriptable `ContactSyncing` conformer. Records every RPC; the test sets
/// scripted responses before driving the controller.
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

    private let lock = NSLock()

    private var _checkSyncCalls: [Data] = []
    private var _deltaCalls:     [DeltaCall] = []
    private var _fullCalls:      [FullCall] = []
    private var _streamCalls:    [Data] = []

    private var _checkSyncResult:    Result<CheckSyncResult, Error>   = .success(.ok)
    private var _deltaUploadResult:  Result<DeltaUploadResult, Error> = .success(.ok)
    private var _fullUploadResult:   Result<Void, Error>              = .success(())
    private var _streamYields:       [String] = []
    private var _streamTerminalError: Error?

    var checkSyncCalls: [Data]    { lock.withLock { _checkSyncCalls } }
    var deltaCalls:     [DeltaCall] { lock.withLock { _deltaCalls } }
    var fullCalls:      [FullCall]  { lock.withLock { _fullCalls } }
    var streamCalls:    [Data]    { lock.withLock { _streamCalls } }

    var checkSyncResult: Result<CheckSyncResult, Error> {
        get { lock.withLock { _checkSyncResult } }
        set { lock.withLock { _checkSyncResult = newValue } }
    }
    var deltaUploadResult: Result<DeltaUploadResult, Error> {
        get { lock.withLock { _deltaUploadResult } }
        set { lock.withLock { _deltaUploadResult = newValue } }
    }
    var fullUploadResult: Result<Void, Error> {
        get { lock.withLock { _fullUploadResult } }
        set { lock.withLock { _fullUploadResult = newValue } }
    }
    var streamYields: [String] {
        get { lock.withLock { _streamYields } }
        set { lock.withLock { _streamYields = newValue } }
    }
    var streamTerminalError: Error? {
        get { lock.withLock { _streamTerminalError } }
        set { lock.withLock { _streamTerminalError = newValue } }
    }

    // MARK: - ContactSyncing -

    func checkContactSync(checksum: Data, owner: KeyPair) async throws -> CheckSyncResult {
        let scripted: Result<CheckSyncResult, Error> = lock.withLock {
            _checkSyncCalls.append(checksum)
            return _checkSyncResult
        }
        return try scripted.get()
    }

    func uploadContactDelta(
        adds: [String],
        removes: [String],
        oldChecksum: Data,
        newChecksum: Data,
        owner: KeyPair
    ) async throws -> DeltaUploadResult {
        let scripted: Result<DeltaUploadResult, Error> = lock.withLock {
            _deltaCalls.append(DeltaCall(
                adds:        adds,
                removes:     removes,
                oldChecksum: oldChecksum,
                newChecksum: newChecksum
            ))
            return _deltaUploadResult
        }
        return try scripted.get()
    }

    func uploadAllContacts(phones: [String], checksum: Data, owner: KeyPair) async throws {
        let scripted: Result<Void, Error> = lock.withLock {
            _fullCalls.append(FullCall(phones: phones, checksum: checksum))
            return _fullUploadResult
        }
        try scripted.get()
    }

    func streamFlipcashContacts(checksum: Data, owner: KeyPair) -> AsyncThrowingStream<String, Error> {
        lock.withLock { _streamCalls.append(checksum) }
        return AsyncThrowingStream { [self] continuation in
            // Reads scripted values inside the producer so mutations after
            // construction (but before iteration) take effect.
            let (yields, terminalError): ([String], Error?) = lock.withLock {
                (_streamYields, _streamTerminalError)
            }
            for value in yields {
                continuation.yield(value)
            }
            if let terminalError {
                continuation.finish(throwing: terminalError)
            } else {
                continuation.finish()
            }
            continuation.onTermination = { _ in }
        }
    }
}
