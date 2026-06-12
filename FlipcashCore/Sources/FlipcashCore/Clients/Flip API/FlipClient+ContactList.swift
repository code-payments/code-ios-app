//
//  FlipClient+ContactList.swift
//  FlipcashCore
//

import Foundation

extension FlipClient {

    public func checkContactSync(checksum: Data, owner: KeyPair) async throws -> CheckSyncResult {
        try await withCheckedThrowingContinuation { c in
            contactListService.checkSync(checksum: checksum, owner: owner) { c.resume(with: $0) }
        }
    }

    public func uploadContactDelta(
        adds: [String],
        removes: [String],
        oldChecksum: Data,
        newChecksum: Data,
        owner: KeyPair
    ) async throws -> DeltaUploadResult {
        try await withCheckedThrowingContinuation { c in
            contactListService.deltaUpload(
                adds: adds,
                removes: removes,
                oldChecksum: oldChecksum,
                newChecksum: newChecksum,
                owner: owner
            ) { c.resume(with: $0) }
        }
    }

    public func uploadAllContacts(phones: [String], checksum: Data, owner: KeyPair) async throws {
        try await withCheckedThrowingContinuation { c in
            contactListService.fullUpload(phones: phones, checksum: checksum, owner: owner) { c.resume(with: $0) }
        }
    }

    /// Yields each matched contact individually. Throws on `denied`,
    /// `checksumDrift`, or network failure; `notFound` is a successful
    /// 0-match completion. Cancelling the consuming task cancels the call.
    public func streamFlipcashContacts(checksum: Data, owner: KeyPair) -> AsyncThrowingStream<MatchedContact, Error> {
        AsyncThrowingStream { continuation in
            let cancellable = contactListService.getFlipcashContacts(
                checksum: checksum,
                owner: owner
            ) { batch in
                for contact in batch.contacts {
                    continuation.yield(contact)
                }
                switch batch.result {
                case .ok, .notFound:
                    break
                case .denied:
                    continuation.finish(throwing: ErrorContactSync.denied)
                case .checksumDrift:
                    continuation.finish(throwing: ErrorContactSync.checksumDrift)
                case .unknown:
                    continuation.finish(throwing: ErrorContactSync.unknown)
                }
            } onCompletion: { result in
                switch result {
                case .success: continuation.finish()
                case .failure(let error): continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }
}
