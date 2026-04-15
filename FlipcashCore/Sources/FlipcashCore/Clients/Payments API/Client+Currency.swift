//
//  Client+Currency.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI

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

    public func checkAvailability(name: String) async throws -> Bool {
        try await withCheckedThrowingContinuation { c in
            currencyService.checkAvailability(name: name) { c.resume(with: $0) }
        }
    }

    public func launch(
        name: String,
        symbol: String?,
        description: String?,
        billCustomization: Ocp_Currency_V1_BillCustomization?,
        icon: Data?,
        nameAttestation: ModerationAttestation,
        symbolAttestation: ModerationAttestation?,
        descriptionAttestation: ModerationAttestation?,
        iconAttestation: ModerationAttestation?,
        owner: KeyPair
    ) async throws -> PublicKey {
        try await withCheckedThrowingContinuation { c in
            currencyService.launch(
                name: name,
                symbol: symbol,
                description: description,
                billCustomization: billCustomization,
                icon: icon,
                nameAttestation: nameAttestation,
                symbolAttestation: symbolAttestation,
                descriptionAttestation: descriptionAttestation,
                iconAttestation: iconAttestation,
                owner: owner
            ) { c.resume(with: $0) }
        }
    }

    /// Launches a new currency using hex color strings for bill customization.
    /// Callers outside FlipcashCore can use this overload without importing
    /// `FlipcashAPI` to construct the proto `BillCustomization` directly.
    public func launch(
        name: String,
        symbol: String?,
        description: String?,
        billColors: [String],
        icon: Data?,
        nameAttestation: ModerationAttestation,
        symbolAttestation: ModerationAttestation?,
        descriptionAttestation: ModerationAttestation?,
        iconAttestation: ModerationAttestation?,
        owner: KeyPair
    ) async throws -> PublicKey {
        let billCustomization = Ocp_Currency_V1_BillCustomization.with {
            $0.colors = billColors.map { hex in
                Ocp_Currency_V1_Color.with { $0.hex = hex }
            }
        }
        return try await launch(
            name: name,
            symbol: symbol,
            description: description,
            billCustomization: billCustomization,
            icon: icon,
            nameAttestation: nameAttestation,
            symbolAttestation: symbolAttestation,
            descriptionAttestation: descriptionAttestation,
            iconAttestation: iconAttestation,
            owner: owner
        )
    }
}
