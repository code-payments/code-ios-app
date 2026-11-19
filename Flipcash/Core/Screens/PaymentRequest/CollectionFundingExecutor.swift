//
//  CollectionFundingExecutor.swift
//  Flipcash
//

import Foundation
import FlipcashCore

/// One funding leg as a swap: sell `amount` worth of `source` into `destination`, where `amount`
/// is what leaves the source before its sell fee, in the request's currency.
struct CollectionFundingSwap: Equatable, Sendable {
    let source: PublicKey
    let destination: PublicKey
    let amount: FiatAmount
}

/// The swap operations a collection payment's funding legs run, so the executor can be tested
/// without a network.
@MainActor
protocol CollectionSwapping: AnyObject {

    /// Submits `swap` under `swapID`.
    func submit(_ swap: CollectionFundingSwap, swapID: SwapId) async throws

    /// The swap's current state, or nil when the server has no swap under `swapID`.
    func state(of swapID: SwapId) async throws -> SwapState?

    /// Waits for the swap to reach a terminal state and returns the last state seen, which is
    /// non-terminal when the wait ran out.
    func waitForTerminalState(of swapID: SwapId) async throws -> SwapState

    /// Reloads balances, so the next plan reads what the finished swaps delivered.
    func refreshBalances() async throws
}

/// Runs a collection payment's funding legs: each conversion swaps into the paying currency and
/// settles before the next starts, then the balances are read again and the plan rebuilt from
/// them, until the paying currency covers the payment.
@MainActor
final class CollectionFundingExecutor {

    enum Outcome: Equatable {
        /// The paying currency now covers the payment.
        case funded
        /// The balances can't cover it without adding money.
        case short
        /// A swap failed, was refused, or didn't settle in time.
        case failed
    }

    /// Plans rebuilt after legs land. A leg that delivers a little less than planned, because the
    /// price moved, leaves a remainder the next round converts.
    static let maxRounds = 3

    private let swapper: any CollectionSwapping
    private let store: CollectionFundingStore

    init(swapper: any CollectionSwapping, store: CollectionFundingStore) {
        self.swapper = swapper
        self.store = store
    }

    /// Funds `requestID`'s payment. `plan` builds a plan from the current balances; it is called
    /// before the first round and after each one.
    func fund(
        _ requestID: PaymentRequestID,
        currency: CurrencyCode,
        plan: () -> CollectionFundingPlan?
    ) async -> Outcome {
        for _ in 0..<Self.maxRounds {
            guard let plan = plan(), plan.payableWithoutTopUp,
                  let paying = try? PublicKey(base58: plan.payingCurrency) else { return .short }
            let legs = plan.legs.filter { $0.conversion && $0.soldMicros > 0 }
            if legs.isEmpty { return .funded }

            for leg in legs {
                guard let source = try? PublicKey(base58: leg.source) else { return .failed }
                let swap = CollectionFundingSwap(
                    source: source,
                    destination: paying,
                    amount: FiatAmount(value: Decimal(leg.soldMicros) / 1_000_000, currency: currency)
                )
                guard await run(swap, source: leg.source, for: requestID) else { return .failed }
            }

            do {
                try await swapper.refreshBalances()
            } catch {
                return .failed
            }
        }
        // Still converting after every round: treat it as short rather than swap without end.
        return .short
    }

    /// Runs one leg to a terminal state. A swap id already stored for the leg is looked up first:
    /// a swap the server has, in any state, is waited on and never submitted again; one it has no
    /// record of is submitted under the same id.
    private func run(_ swap: CollectionFundingSwap, source: String, for requestID: PaymentRequestID) async -> Bool {
        var swapID = store.swapID(for: requestID, source: source)
        var submit = true

        if let stored = swapID {
            do {
                switch try await swapper.state(of: stored) {
                case nil:
                    break
                case .finalized?:
                    // It landed before the last attempt ended; the plan this round was read
                    // before balances caught up, so don't convert again.
                    store.removeSwapID(for: requestID, source: source)
                    return true
                case .failed?, .cancelled?:
                    // Its funds came back; this attempt needs a swap of its own.
                    store.removeSwapID(for: requestID, source: source)
                    swapID = nil
                case .some:
                    submit = false
                }
            } catch {
                return false
            }
        }

        let id = swapID ?? SwapId.generate()
        if submit {
            store.setSwapID(id, for: requestID, source: source)
            do {
                try await swapper.submit(swap, swapID: id)
            } catch {
                // The outcome is unknown, so keep the id: a retry asks the server about it first.
                return false
            }
        }

        let state: SwapState
        do {
            state = try await swapper.waitForTerminalState(of: id)
        } catch {
            return false
        }
        switch state {
        case .finalized:
            store.removeSwapID(for: requestID, source: source)
            return true
        case .failed, .cancelled:
            store.removeSwapID(for: requestID, source: source)
            return false
        case .unknown, .created, .funding, .funded, .submitting, .cancelling:
            // Not settled in time; keep the id for the retry.
            return false
        }
    }
}

// MARK: - Session -

/// Funding legs as real swaps, priced the way Convert prices them: the source amount at a fresh
/// pin for the source mint.
@MainActor
final class SessionCollectionSwapper: CollectionSwapping {

    enum Error: Swift.Error {
        case rateUnavailable
    }

    /// Polls at the inline swap cadence for up to 30 seconds per leg.
    static let pollAttempts = 120

    private let session: Session
    private let ratesController: RatesController

    init(session: Session, ratesController: RatesController) {
        self.session = session
        self.ratesController = ratesController
    }

    func submit(_ swap: CollectionFundingSwap, swapID: SwapId) async throws {
        guard let pin = await ratesController.currentPinnedState(for: swap.amount.currency, mint: swap.source),
              let amount = session.price(swap.amount, mint: swap.source, at: pin) else {
            throw Error.rateUnavailable
        }
        if swap.destination == .usdf {
            _ = try await session.sell(amount: amount, verifiedState: pin, in: swap.source, swapId: swapID)
        } else if swap.source == .usdf {
            _ = try await session.buy(amount: amount, feeAmount: nil, verifiedState: pin, of: swap.destination, swapId: swapID)
        } else {
            _ = try await session.buy(amount: amount, with: swap.source, verifiedState: pin, of: swap.destination, swapId: swapID)
        }
    }

    func state(of swapID: SwapId) async throws -> SwapState? {
        try await session.swapState(swapId: swapID)
    }

    func waitForTerminalState(of swapID: SwapId) async throws -> SwapState {
        do {
            return try await session.pollSwapState(
                swapId: swapID,
                maxAttempts: Self.pollAttempts,
                interval: InlineCompletion.pollInterval
            ).state
        } catch ClientError.swapDenied, ClientError.swapRejected {
            return .failed
        }
    }

    func refreshBalances() async throws {
        try await session.fetchBalance()
    }
}
