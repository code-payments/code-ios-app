//
//  InlineBalanceCompletion.swift
//  Flipcash
//

import Foundation
import FlipcashCore

// MARK: - AddMoneyTiming -

/// Timing for add money's chain- and indexing-bound waits. Solana's Alpenglow upgrade shortens
/// on-chain finality, so these poll faster than they used to while keeping the same total wall time.
nonisolated enum AddMoneyTiming {

    /// Delay between USDC sweep attempts on the processing screen.
    static let sweepBackoff: Duration = .seconds(1)

    /// Sweep attempts; with `sweepBackoff` this keeps the earlier ~60s budget (20 attempts at 3s).
    static let sweepMaxAttempts = 60

    /// Delay between USDF balance refreshes on the processing screen.
    static let balancePollInterval: Duration = .milliseconds(500)

    /// How long the processing screen waits for the credit before reporting a failure.
    static let settlementTimeout: Duration = .seconds(120)
}

// MARK: - AddMoneyBalanceTarget -

/// The USDF balance that counts as a finished deposit.
nonisolated enum AddMoneyBalanceTarget {

    /// Onramp fees deliver slightly less than the requested amount, so accept
    /// a small shortfall rather than poll forever for the exact figure.
    static let tolerance: Decimal = 0.98

    static func target(baseline: FiatAmount, amount: ExchangedFiat) -> FiatAmount {
        baseline + amount.usdfValue * tolerance
    }
}

// MARK: - InlineBalanceCompletion -

/// Waits for a just-submitted deposit to credit the USDF balance on the screen that submitted it.
/// The balance counterpart of `InlineSwapCompletion`, sharing `InlineCompletion`'s window and
/// interval. There is no failure outcome: a deposit that has not landed is still pending, and the
/// processing screen owns the timeout verdict.
@MainActor
struct InlineBalanceCompletion {

    enum Outcome: Equatable {
        /// The balance reached the target.
        case succeeded
        /// Not credited within the window; the processing screen takes over.
        case pending
    }

    let settlement: any AddMoneySettling
    let target: FiatAmount
    var window: Duration = InlineCompletion.window
    var interval: Duration = InlineCompletion.pollInterval

    func awaitOutcome() async -> Outcome {
        let deadline = ContinuousClock.now.advanced(by: window)
        while true {
            settlement.updateBalance()
            if let current = settlement.balance(for: .usdf)?.usdf, current >= target {
                return .succeeded
            }
            guard ContinuousClock.now < deadline else { return .pending }
            do {
                try await Task.sleep(for: interval)
            } catch {
                // The deposit is already submitted, so a cancelled wait is not a failure.
                return .pending
            }
        }
    }
}
