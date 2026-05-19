//
//  ClientCapabilities.swift
//  FlipcashCore
//

import Foundation

// Capability protocols expose narrow slices of `Client` so operations and
// other callers can depend on a single concern (and tests can substitute a
// fake) without pulling in the whole client. One concern per protocol —
// avoid bundling unrelated methods into a "ClientLike" mega-protocol.

/// Read the user's plain SPL associated token account for a given mint.
public protocol AssociatedTokenAccountFetching: Sendable {
    func fetchAssociatedTokenAccount(owner: KeyPair, mint: PublicKey) async throws -> AccountInfo?
}

/// Execute a Coinbase Stable Swapper stateless swap (used by the on-app-open
/// USDC → USDF sweep).
public protocol StatelessSwapping: Sendable {
    func statelessSwap(
        fromMint: MintMetadata,
        toMint: MintMetadata,
        amount: TokenAmount,
        owner: KeyPair
    ) async throws -> StatelessSwapResult
}

extension Client: AssociatedTokenAccountFetching, StatelessSwapping {}
