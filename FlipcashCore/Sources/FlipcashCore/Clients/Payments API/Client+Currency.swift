//
//  Client+Currency.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

extension Client {
    public func fetchMint(mint: PublicKey) async throws -> MintMetadata {
        try await withCheckedThrowingContinuation { c in
            currencyService.fetchMint(mint: mint) { c.resume(with: $0) }
        }
    }
    
    public func fetchMints(mints: [PublicKey]) async throws -> [PublicKey: MintMetadata] {
        try await withCheckedThrowingContinuation { c in
            currencyService.fetchMints(mints: mints) { c.resume(with: $0) }
        }
    }

    public func fetchHistoricalMintData(mint: PublicKey, range: HistoricalRange, currencyCode: String) async throws -> [HistoricalMintDataPoint] {
        try await withCheckedThrowingContinuation { c in
            currencyService.fetchHistoricalMintData(mint: mint, range: range, currencyCode: currencyCode) { c.resume(with: $0) }
        }
    }

    /// Returns an `AsyncThrowingStream` of currency batches for the given category.
    ///
    /// Each yielded array is a complete ranked snapshot (not a delta). The stream
    /// finishes when the server closes the connection successfully, or throws on
    /// gRPC errors. Cancelling the consuming `Task` (e.g. via `.task(id:)`) tears
    /// down the underlying gRPC stream.
    public func discoverCurrencies(category: DiscoverCategory) -> AsyncThrowingStream<[MintMetadata], Error> {
        AsyncThrowingStream { continuation in
            let ref = currencyService.discover(category: category) { mints in
                continuation.yield(mints)
            }

            ref.stream?.status.whenComplete { result in
                switch result {
                case .success(let status) where status.code == .ok:
                    continuation.finish()
                case .success(let status):
                    continuation.finish(throwing: status)
                case .failure(let error):
                    continuation.finish(throwing: error)
                }
            }

            nonisolated(unsafe) let unsafeRef = ref
            continuation.onTermination = { @Sendable _ in
                unsafeRef.cancel()
            }
        }
    }
}
