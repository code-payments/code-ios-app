//
//  Client+Transaction.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

private let logger = Logger(label: "flipcash.payment-client")

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
    
    public func transfer(exchangedFiat: ExchangedFiat, verifiedState: VerifiedState, owner: AccountCluster, destination: PublicKey, destinationOwner: PublicKey? = nil, chatMetadata: ChatPaymentMetadata? = nil, rendezvous: PublicKey) async throws {
        let appMetadata = try chatMetadata?.serializedAppMetadata()
        _ = try await withCheckedThrowingContinuation { c in
            transactionService.transfer(
                exchangedFiat: exchangedFiat,
                verifiedState: verifiedState,
                sourceCluster: owner,
                destination: destination,
                destinationOwner: destinationOwner,
                appMetadata: appMetadata,
                owner: owner.authority.keyPair,
                rendezvous: rendezvous
            ) { c.resume(with: $0) }
        }
    }

    public func withdraw(exchangedFiat: ExchangedFiat, verifiedState: VerifiedState, fee: TokenAmount, owner: AccountCluster, destinationMetadata: DestinationMetadata) async throws {
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

    public func sendCashLink(exchangedFiat: ExchangedFiat, verifiedState: VerifiedState, ownerCluster: AccountCluster, giftCard: GiftCardCluster, rendezvous: PublicKey) async throws(ErrorSubmitIntent) {
        do {
            _ = try await withCheckedThrowingContinuation { c in
                transactionService.sendCashLink(
                    exchangedFiat: exchangedFiat,
                    verifiedState: verifiedState,
                    ownerCluster: ownerCluster,
                    giftCard: giftCard,
                    rendezvous: rendezvous
                ) { c.resume(with: $0) }
            }
        } catch let error as ErrorSubmitIntent {
            throw error
        } catch {
            throw .grpcError(error)
        }
    }

    public func receiveCashLink(usdf: TokenAmount, ownerCluster: AccountCluster, giftCard: GiftCardCluster) async throws(ErrorSubmitIntent) {
        do {
            _ = try await withCheckedThrowingContinuation { c in
                transactionService.receiveCashLink(
                    usdf: usdf,
                    ownerCluster: ownerCluster,
                    giftCard: giftCard
                ) { c.resume(with: $0) }
            }
        } catch let error as ErrorSubmitIntent {
            throw error
        } catch {
            throw .grpcError(error)
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

    /// Buy tokens paying with another launchpad currency (Phase 1 + Phase 2).
    @discardableResult
    public func buy(amount: ExchangedFiat, with paymentToken: MintMetadata, verifiedState: VerifiedState, of token: MintMetadata, owner: AccountCluster) async throws -> SwapId {
        // Ensure the timelock vault account exists for the target mint
        try await ensureAccountExists(
            owner: owner.authority.keyPair,
            ownerAuthority: owner.authority,
            token: token
        )

        return try await withCheckedThrowingContinuation { c in
            transactionService.buy(amount: amount, with: paymentToken, verifiedState: verifiedState, of: token, owner: owner) { c.resume(with: $0) }
        }
    }

    @discardableResult
    public func sell(amount: ExchangedFiat, verifiedState: VerifiedState, in token: MintMetadata, owner: AccountCluster) async throws -> SwapId {
        try await withCheckedThrowingContinuation { c in
            transactionService.sell(amount: amount, verifiedState: verifiedState, in: token, owner: owner) { c.resume(with: $0) }
        }
    }

    /// Runs a `StatelessSwap` (USDC → USDF via Coinbase Stable Swapper) using
    /// the owner key as both the request signer and the on-chain swap signer.
    /// Used by the on-app-open auto-sweep.
    public func statelessSwap(
        fromMint: MintMetadata,
        toMint: MintMetadata,
        amount: TokenAmount,
        owner: KeyPair
    ) async throws -> StatelessSwapResult {
        try await withCheckedThrowingContinuation { c in
            transactionService.statelessSwap(
                fromMint: fromMint,
                toMint: toMint,
                amount: amount,
                owner: owner
            ) { c.resume(with: $0) }
        }
    }

    /// Withdraws USDF to a Solana wallet as USDC via Coinbase Stable Swapper.
    /// Phase 1 + Phase 2 mirroring `buy()` — stateful swap stream → IntentFundSwap.
    @discardableResult
    public func withdrawAsUSDC(
        amount: ExchangedFiat,
        verifiedState: VerifiedState,
        destinationOwner: PublicKey,
        fee: TokenAmount,
        sourceCluster: AccountCluster
    ) async throws -> SwapId {
        try await withCheckedThrowingContinuation { continuation in
            transactionService.withdrawAsUSDC(
                amount: amount,
                verifiedState: verifiedState,
                destinationOwner: destinationOwner,
                fee: fee,
                sourceCluster: sourceCluster
            ) { result in
                continuation.resume(with: result)
            }
        }
    }

    /// Buys the first tokens on a newly-launched currency using reserves funding
    /// (Phase 1 stateful swap + Phase 2 `IntentFundSwap`). Without the Phase 2
    /// funding intent the server-side swap sits at `CREATED` and is cancelled
    /// once the blockhash expires.
    @discardableResult
    public func buyNewCurrency(
        swapId: SwapId,
        amount: ExchangedFiat,
        feeAmount: ExchangedFiat,
        verifiedState: VerifiedState,
        mint: PublicKey,
        owner: AccountCluster
    ) async throws -> SwapMetadata {
        try await withCheckedThrowingContinuation { c in
            transactionService.buyNewCurrency(
                swapId: swapId,
                amount: amount,
                feeAmount: feeAmount,
                verifiedState: verifiedState,
                mint: mint,
                owner: owner
            ) { c.resume(with: $0) }
        }
    }

    /// Buys the first tokens on a newly-launched currency, funded by another
    /// launchpad currency rather than USDF reserves.
    @discardableResult
    public func buyNewCurrency(
        swapId: SwapId,
        amount: ExchangedFiat,
        feeAmount: ExchangedFiat,
        verifiedState: VerifiedState,
        paymentToken: MintMetadata,
        mint: PublicKey,
        owner: AccountCluster
    ) async throws -> SwapMetadata {
        try await withCheckedThrowingContinuation { c in
            transactionService.buyNewCurrency(
                swapId: swapId,
                amount: amount,
                feeAmount: feeAmount,
                verifiedState: verifiedState,
                paymentToken: paymentToken,
                mint: mint,
                owner: owner
            ) { c.resume(with: $0) }
        }
    }

    // MARK: - Status -
    
    public func pollIntentMetadata(owner: KeyPair, intentID: PublicKey, maxAttempts: Int = 50) async throws -> IntentMetadata {
        logger.debug("Polling intent metadata", metadata: ["intentId": "\(intentID.base58)", "maxAttempts": "\(maxAttempts)"])
        for i in 0..<maxAttempts {
            do {
                let delay = 50 * (i / 10)
                if delay > 0 {
                    try await Task.delay(milliseconds: delay)
                }
                return try await fetchIntentMetadata(owner: owner, intentID: intentID)
            } catch ErrorFetchIntentMetadata.denied {
                logger.warning("Intent denied (grabbed by another device)", metadata: ["intentId": "\(intentID.base58)"])
                throw ClientError.denied
            } catch {}
        }

        logger.error("Poll limit reached for intent", metadata: ["intentId": "\(intentID.base58)"])
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
    /// - Returns: Final SwapMetadata when a terminal state is reached, or the
    ///   last-fetched metadata when the poll budget is exhausted — callers
    ///   treat a returned non-terminal state as a timeout.
    /// - Throws: ClientError.pollLimitReached if max attempts are exceeded
    ///   without ever fetching swap state
    public func pollSwapState(
        swapId: SwapId,
        owner: KeyPair,
        maxAttempts: Int,
        onStateChange: (@Sendable (SwapState) -> Void)? = nil
    ) async throws -> SwapMetadata {
        try await pollSwapTerminalState(
            swapId: swapId,
            maxAttempts: maxAttempts,
            onStateChange: onStateChange,
            fetch: { try await self.fetchSwapMetadata(swapId: swapId, owner: owner) }
        )
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

// MARK: - Poll helpers (testable) -

/// Polls `fetch` until the swap reaches a terminal state or `maxAttempts` is
/// exhausted. On exhaustion, returns the last-fetched metadata so callers can
/// see the state the swap was stuck in; throws
/// ``ClientError/pollLimitReached`` only when no swap state was ever fetched.
func pollSwapTerminalState(
    swapId: SwapId,
    maxAttempts: Int,
    pollInterval: Duration = .seconds(1),
    onStateChange: (@Sendable (SwapState) -> Void)? = nil,
    fetch: @Sendable () async throws -> SwapMetadata
) async throws -> SwapMetadata {
    var lastMetadata: SwapMetadata?

    for i in 0..<maxAttempts {
        if i > 0 {
            try await Task.sleep(for: pollInterval)
        }

        logger.debug("Polling swap state", metadata: [
            "attempt": "\(i + 1)/\(maxAttempts)",
            "swapId": "\(swapId.publicKey.base58)"
        ])

        do {
            let metadata = try await fetch()

            // Notify of state change
            if metadata.state != lastMetadata?.state {
                onStateChange?(metadata.state)
            }
            lastMetadata = metadata

            // Check for terminal states
            switch metadata.state {
            case .finalized, .failed, .cancelled:
                logger.info("Swap reached terminal state", metadata: ["state": "\(metadata.state)"])
                return metadata
            case .unknown, .created, .funding, .funded, .submitting, .cancelling:
                // Continue polling
                continue
            }
        } catch ErrorGetSwap.notFound {
            // Swap not yet visible — service layer already logs this at
            // debug level. Continue polling.
            continue
        } catch {
            // Log but continue polling for transient errors
            logger.warning("Swap poll error, continuing", metadata: ["error": "\(error)"])
            continue
        }
    }

    logger.error("Poll limit reached for swap", metadata: [
        "swapId": "\(swapId.publicKey.base58)",
        "maxAttempts": "\(maxAttempts)",
        "lastState": "\(lastMetadata.map { "\($0.state)" } ?? "<never fetched>")"
    ])

    guard let lastMetadata else {
        throw ClientError.pollLimitReached
    }
    return lastMetadata
}

// MARK: - Error -

public enum ClientError: Error {
    case pollLimitReached
    case denied
    case vmMetadataMissing
}
