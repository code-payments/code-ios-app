//
//  UsdcSweepOperation.swift
//  Flipcash
//

import Foundation
import FlipcashCore

private nonisolated let logger = Logger(label: "flipcash.usdc-sweep")

/// Converts the user's USDC ATA balance into USDF via `StatelessSwap`.
/// Re-entrant invocations while a sweep is in flight are skipped.
actor UsdcSweepOperation {

    private let accountFetcher: any AssociatedTokenAccountFetching
    private let swapper: any StatelessSwapping
    private let ownerKeyPair: KeyPair
    private let onSweepCompleted: @Sendable () async -> Void
    private let cancellation = SweepCancellation()

    private var isRunning = false

    init(
        accountFetcher: any AssociatedTokenAccountFetching,
        swapper: any StatelessSwapping,
        ownerKeyPair: KeyPair,
        onSweepCompleted: @escaping @Sendable () async -> Void
    ) {
        self.accountFetcher = accountFetcher
        self.swapper = swapper
        self.ownerKeyPair = ownerKeyPair
        self.onSweepCompleted = onSweepCompleted
    }

    /// Spawns the sweep task and returns it. No-op when one is already in flight.
    @discardableResult
    nonisolated func start() -> Task<Void, Never> {
        Task { await run() }
    }

    /// Marks the operation as cancelled. Any in-flight sweep runs to
    /// completion (the gRPC stream isn't interrupted), but the completion
    /// callback is skipped so a logged-out session can't be touched. Called
    /// from `SessionAuthenticator.logout()` before tearing down the container.
    nonisolated func cancel() {
        cancellation.cancel()
    }

    private func run() async {
        guard !isRunning else {
            logger.info("Skipping USDC sweep — already in flight")
            return
        }
        isRunning = true
        defer { isRunning = false }

        do {
            guard let account = try await accountFetcher.fetchAssociatedTokenAccount(
                owner: ownerKeyPair,
                mint: .usdc
            ) else {
                logger.info("No USDC ATA found — nothing to sweep")
                return
            }

            guard !cancellation.isCancelled else {
                logger.info("USDC sweep cancelled before swap")
                return
            }

            guard account.quarks > 0 else {
                logger.info("USDC ATA balance is zero — nothing to sweep")
                return
            }

            logger.info("Sweeping USDC balance", metadata: [
                "quarks": "\(account.quarks)",
            ])

            let amount = TokenAmount(quarks: account.quarks, mint: .usdc)
            let result = try await swapper.statelessSwap(
                fromMint: .usdc,
                toMint: .usdf,
                amount: amount,
                owner: ownerKeyPair
            )

            logger.info("USDC sweep completed", metadata: [
                "signature": "\(result.signature.base58)",
            ])

            guard !cancellation.isCancelled else {
                logger.info("USDC sweep cancelled, skipping completion callback")
                return
            }

            await onSweepCompleted()
        } catch {
            logger.error("USDC sweep failed", metadata: [
                "error": "\(error)",
            ])
            await ErrorReporting.captureError(error, reason: "USDC sweep failed")
        }
    }

    /// Retrying, caller-driven sweep for the in-app "Add Money" deposit flow.
    ///
    /// Unlike the app-active `start()` (fires once per activation, re-entrancy
    /// gated), this is an explicit trigger the Adding Money screen drives after a
    /// Coinbase / Other Wallet deposit: each attempt fetches the USDC ATA and,
    /// once USDC has landed, runs a single `statelessSwap` and returns `true`. If
    /// USDC isn't present yet it backs off and retries. Returns `false` when the
    /// attempts are exhausted without a sweep.
    ///
    /// Does not fire `onSweepCompleted` — the caller observes the USDF balance
    /// itself and owns the post-transaction refresh.
    ///
    /// - Parameters:
    ///   - expectedAtLeast: Minimum USDC that must be present before sweeping.
    ///     Defaults to any positive balance.
    ///   - maxAttempts: Number of fetch attempts before giving up (clamped to ≥1).
    ///   - backoff: Delay between attempts.
    func sweepUntilConverted(
        expectedAtLeast: TokenAmount? = nil,
        maxAttempts: Int,
        backoff: Duration
    ) async -> Bool {
        let attempts = max(1, maxAttempts)
        let required = max(expectedAtLeast?.quarks ?? 1, 1)

        for attempt in 1...attempts {
            if Task.isCancelled || cancellation.isCancelled {
                logger.info("Retrying USDC sweep cancelled")
                return false
            }

            do {
                let account = try await accountFetcher.fetchAssociatedTokenAccount(
                    owner: ownerKeyPair,
                    mint: .usdc
                )
                let available = account?.quarks ?? 0

                if available >= required {
                    logger.info("Retrying USDC sweep found balance, converting", metadata: [
                        "attempt": "\(attempt)",
                        "quarks": "\(available)",
                    ])

                    let amount = TokenAmount(quarks: available, mint: .usdc)
                    let result = try await swapper.statelessSwap(
                        fromMint: .usdc,
                        toMint: .usdf,
                        amount: amount,
                        owner: ownerKeyPair
                    )

                    logger.info("Retrying USDC sweep completed", metadata: [
                        "signature": "\(result.signature.base58)",
                    ])
                    return true
                }
            } catch {
                logger.error("Retrying USDC sweep attempt failed", metadata: [
                    "attempt": "\(attempt)",
                    "error": "\(error)",
                ])
                await ErrorReporting.captureError(error, reason: "Retrying USDC sweep attempt failed")
            }

            if attempt < attempts {
                try? await Task.sleep(for: backoff)
            }
        }

        logger.info("Retrying USDC sweep exhausted attempts without converting")
        return false
    }
}

/// Thread-safe cancellation flag shared between the actor's async `run()` and
/// the synchronous `nonisolated cancel()` (called from `logout()`).
private nonisolated final class SweepCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}
