//
//  Client+Transaction.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import Combine

extension Client {
 
    public func createAccounts(owner: KeyPair, mint: PublicKey, cluster: AccountCluster, kind: AccountKind, derivationIndex: Int) async throws {
        _ = try await withCheckedThrowingContinuation { c in
            transactionService.createAccounts(owner: owner, mint: mint, cluster: cluster, kind: kind, derivationIndex: derivationIndex) { c.resume(with: $0) }
        }
    }

    /// Ensures that a timelock vault account exists for the given mint.
    /// This is a no-op if the account already exists.
    ///
    /// - Parameters:
    ///   - owner: The owner's keypair for signing
    ///   - ownerAuthority: The owner's authority (DerivedKey)
    ///   - token: The mint metadata containing VM authority information
    public func ensureAccountExists(owner: KeyPair, ownerAuthority: DerivedKey, token: MintMetadata) async throws {
        guard let vmMetadata = token.vmMetadata else {
            throw ClientError.vmMetadataMissing
        }

        let cluster = AccountCluster(
            authority: ownerAuthority,
            mint: token.address,
            timeAuthority: vmMetadata.authority
        )

        try await createAccounts(
            owner: owner,
            mint: token.address,
            cluster: cluster,
            kind: .primary,
            derivationIndex: 0
        )
    }
    
    public func transfer(exchangedFiat: ExchangedFiat, verifiedState: VerifiedState, owner: AccountCluster, destination: PublicKey, rendezvous: PublicKey) async throws {
        _ = try await withCheckedThrowingContinuation { c in
            transactionService.transfer(
                exchangedFiat: exchangedFiat,
                verifiedState: verifiedState,
                sourceCluster: owner,
                destination: destination,
                owner: owner.authority.keyPair,
                rendezvous: rendezvous
            ) { c.resume(with: $0) }
        }
    }

    public func withdraw(exchangedFiat: ExchangedFiat, verifiedState: VerifiedState, fee: Quarks, owner: AccountCluster, destinationMetadata: DestinationMetadata) async throws {
        _ = try await withCheckedThrowingContinuation { c in
            transactionService.withdraw(
                exchangedFiat: exchangedFiat,
                verifiedState: verifiedState,
                fee: fee,
                sourceCluster: owner,
                destinationMetadata: destinationMetadata,
                owner: owner.authority.keyPair
            ) { c.resume(with: $0) }
        }
    }

    public func sendCashLink(exchangedFiat: ExchangedFiat, verifiedState: VerifiedState, ownerCluster: AccountCluster, giftCard: GiftCardCluster, rendezvous: PublicKey) async throws {
        _ = try await withCheckedThrowingContinuation { c in
            transactionService.sendCashLink(
                exchangedFiat: exchangedFiat,
                verifiedState: verifiedState,
                ownerCluster: ownerCluster,
                giftCard: giftCard,
                rendezvous: rendezvous
            ) { c.resume(with: $0) }
        }
    }
    
    public func receiveCashLink(usdf: Quarks, ownerCluster: AccountCluster, giftCard: GiftCardCluster) async throws {
        _ = try await withCheckedThrowingContinuation { c in
            transactionService.receiveCashLink(
                usdf: usdf,
                ownerCluster: ownerCluster,
                giftCard: giftCard
            ) { c.resume(with: $0) }
        }
    }
    
    public func voidCashLink(giftCardVault: PublicKey, owner: KeyPair) async throws {
        try await withCheckedThrowingContinuation { c in
            transactionService.voidCashLink(giftCardVault: giftCardVault, owner: owner) { c.resume(with: $0) }
        }
    }
    
    // MARK: - Swaps -

    /// Buy tokens using default submitIntent funding (Phase 1 + Phase 2)
    @discardableResult
    public func buy(amount: ExchangedFiat, verifiedState: VerifiedState, of token: MintMetadata, owner: AccountCluster) async throws -> SwapId {
        // Ensure the timelock vault account exists for this mint
        try await ensureAccountExists(
            owner: owner.authority.keyPair,
            ownerAuthority: owner.authority,
            token: token
        )

        return try await withCheckedThrowingContinuation { c in
            transactionService.buy(amount: amount, verifiedState: verifiedState, of: token, owner: owner) { c.resume(with: $0) }
        }
    }

    /// Buy tokens with specified funding source
    /// - For `.submitIntent`: Phase 1 (startSwap) + Phase 2 (IntentFundSwap)
    /// - For `.externalWallet`: Phase 1 only (funding already happened via external wallet)
    @discardableResult
    public func buy(swapId: SwapId, amount: ExchangedFiat, verifiedState: VerifiedState, of token: MintMetadata, owner: AccountCluster, fundingSource: FundingSource) async throws -> SwapId {
        // Ensure the timelock vault account exists for this mint
        try await ensureAccountExists(
            owner: owner.authority.keyPair,
            ownerAuthority: owner.authority,
            token: token
        )

        return try await withCheckedThrowingContinuation { c in
            transactionService.buy(swapId: swapId, amount: amount, verifiedState: verifiedState, of: token, owner: owner, fundingSource: fundingSource) { c.resume(with: $0) }
        }
    }

    @discardableResult
    public func sell(amount: ExchangedFiat, verifiedState: VerifiedState, in token: MintMetadata, owner: AccountCluster) async throws -> SwapId {
        try await withCheckedThrowingContinuation { c in
            transactionService.sell(amount: amount, verifiedState: verifiedState, in: token, owner: owner) { c.resume(with: $0) }
        }
    }
    
    // MARK: - Status -
    
    public func pollIntentMetadata(owner: KeyPair, intentID: PublicKey, maxAttempts: Int = 50) async throws -> IntentMetadata {
        trace(.poll, components: "Intent: \(intentID.base58), max \(maxAttempts) attempts")
        for i in 0..<maxAttempts {
            do {
                let delay = 50 * (i / 10)
                if delay > 0 {
                    try await Task.delay(milliseconds: delay)
                }
                return try await fetchIntentMetadata(owner: owner, intentID: intentID)
            } catch ErrorFetchIntentMetadata.denied {
                trace(.warning, components: "Intent denied (grabbed by another device): \(intentID.base58)")
                throw ClientError.denied
            } catch {}
        }

        trace(.failure, components: "Poll limit reached for intent: \(intentID.base58)")
        throw ClientError.pollLimitReached
    }
    
    func fetchIntentMetadata(owner: KeyPair, intentID: PublicKey) async throws -> IntentMetadata {
        try await withCheckedThrowingContinuation { c in
            transactionService.fetchIntentMetadata(owner: owner, intentID: intentID) { c.resume(with: $0) }
        }
    }

    // MARK: - Swap Status -

    /// Fetches the current state of a swap
    public func fetchSwapMetadata(swapId: SwapId, owner: KeyPair) async throws -> SwapMetadata {
        try await withCheckedThrowingContinuation { c in
            transactionService.swapService.getSwap(swapId: swapId, owner: owner) { result in
                switch result {
                case .success(let metadata):
                    c.resume(returning: metadata)
                case .failure(let error):
                    c.resume(throwing: error)
                }
            }
        }
    }

    /// Polls swap state until a terminal state is reached or max attempts exceeded.
    ///
    /// Terminal states: `.finalized`, `.failed`, `.cancelled`
    ///
    /// - Parameters:
    ///   - swapId: The swap to poll
    ///   - owner: Owner keypair for authentication
    ///   - maxAttempts: Maximum number of poll attempts
    ///   - onStateChange: Optional callback for state changes (called on each poll)
    /// - Returns: Final SwapMetadata when terminal state is reached
    /// - Throws: ClientError.pollLimitReached if max attempts exceeded
    public func pollSwapState(
        swapId: SwapId,
        owner: KeyPair,
        maxAttempts: Int,
        onStateChange: (@Sendable (SwapState) -> Void)? = nil
    ) async throws -> SwapMetadata {
        var lastState: SwapState?

        for i in 0..<maxAttempts {
            // Backoff strategy: start at 500ms, increase by 100ms every 10 polls
            // Poll 0-9: 500ms, Poll 10-19: 600ms, Poll 20-29: 700ms, etc.
            let delay = 500 + (100 * (i / 10))

            if i > 0 {
                try await Task.delay(milliseconds: delay)
            }

            trace(.poll, components: "SwapState", "Attempt \(i + 1)/\(maxAttempts)", "Delay: \(delay)ms", "Swap ID: \(swapId.publicKey.base58)")

            do {
                let metadata = try await fetchSwapMetadata(swapId: swapId, owner: owner)

                // Notify of state change
                if metadata.state != lastState {
                    lastState = metadata.state
                    onStateChange?(metadata.state)
                }

                // Check for terminal states
                switch metadata.state {
                case .finalized, .failed, .cancelled:
                    trace(.success, components: "SwapState", "Terminal state reached: \(metadata.state)")
                    return metadata
                case .unknown, .created, .funding, .funded, .submitting, .cancelling:
                    // Continue polling
                    continue
                }
            } catch ErrorGetSwap.notFound {
                // Swap not yet visible, continue polling
                trace(.warning, components: "SwapState", "Swap not found yet, continuing...")
                continue
            } catch {
                // Log but continue polling for transient errors
                trace(.warning, components: "SwapState", "Poll error: \(error), continuing...")
                continue
            }
        }

        throw ClientError.pollLimitReached
    }

    // MARK: - Limits -
    
    public func fetchTransactionLimits(owner: KeyPair, since date: Date) async throws -> Limits {
        try await withCheckedThrowingContinuation { c in
            transactionService.fetchTransactionLimits(owner: owner, since: date) { c.resume(with: $0) }
        }
    }
    
    // MARK: - Withdrawals -
    
    public func fetchDestinationMetadata(destination: PublicKey, mint: PublicKey) async -> DestinationMetadata {
        await withCheckedContinuation { c in
            transactionService.fetchDestinationMetadata(destination: destination, mint: mint) { c.resume(with: $0) }
        }
    }
}

// MARK: - Error -

public enum ClientError: Error {
    case pollLimitReached
    case denied
    case vmMetadataMissing
}
