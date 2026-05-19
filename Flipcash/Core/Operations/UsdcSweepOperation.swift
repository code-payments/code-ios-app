//
//  UsdcSweepOperation.swift
//  Flipcash
//

import Foundation
import FlipcashCore

private nonisolated let logger = Logger(label: "flipcash.usdc-sweep-operation")

/// Converts the user's USDC ATA balance into USDF via `StatelessSwap`.
/// Re-entrant invocations while a sweep is in flight are skipped.
actor UsdcSweepOperation {

    private let accountFetcher: any AssociatedTokenAccountFetching
    private let swapper: any StatelessSwapping
    private let ownerKeyPair: KeyPair
    private let onSweepCompleted: @Sendable () async -> Void

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

    /// Spawns the sweep task. No-op when one is already in flight. The
    /// returned Task is for tests that need to await completion; production
    /// callers discard it.
    nonisolated func start() -> Task<Void, Never> {
        Task { await run() }
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

            await onSweepCompleted()
        } catch {
            logger.error("USDC sweep failed", metadata: [
                "error": "\(error)",
            ])
            ErrorReporting.captureError(error, reason: "USDC sweep failed")
        }
    }
}
