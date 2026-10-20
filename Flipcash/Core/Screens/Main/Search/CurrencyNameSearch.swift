//
//  CurrencyNameSearch.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCore

/// Finds currencies by name for Chats Search. The local implementation filters what the app
/// already knows; a server name-search RPC can replace it behind this protocol.
protocol CurrencyNameSearching: Sendable {

    /// The currencies whose name or symbol contains `query`.
    func currencies(matching query: String) async throws -> [MintMetadata]
}

/// Filters the currencies the app already has — held balances, then whatever `Discover` last
/// returned — by name or symbol.
struct LocalCurrencyNameSearch: CurrencyNameSearching {

    private let candidates: @Sendable () async -> [MintMetadata]

    init(candidates: @escaping @Sendable () async -> [MintMetadata]) {
        self.candidates = candidates
    }

    func currencies(matching query: String) async throws -> [MintMetadata] {
        Self.filter(await candidates(), query: query)
    }

    /// The candidates whose name or symbol contains `query`, one per mint, keeping the first
    /// occurrence and its order. When a mint appears more than once, a later copy's Discover metrics
    /// fill in what the first lacks.
    nonisolated static func filter(_ candidates: [MintMetadata], query: String) -> [MintMetadata] {
        var order: [PublicKey] = []
        var byMint: [PublicKey: MintMetadata] = [:]
        for mint in candidates where mint.address != .usdf {
            guard ChatSearchQuery.matches(mint.name, query) || ChatSearchQuery.matches(mint.symbol, query) else { continue }
            if let existing = byMint[mint.address] {
                if existing.marketCapMetrics == nil, mint.marketCapMetrics != nil {
                    byMint[mint.address] = mint
                }
            } else {
                order.append(mint.address)
                byMint[mint.address] = mint
            }
        }
        return order.compactMap { byMint[$0] }
    }
}
