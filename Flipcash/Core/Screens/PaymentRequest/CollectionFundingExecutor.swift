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

/// A swap the server holds unfunded, as GetPendingSwaps lists it.
struct PendingCollectionSwap: Equatable, Sendable {
    let swapID: SwapId
    /// The intent id the server recorded for the swap's funding. Nil when the swap is funded some
    /// other way than an intent this app submits.
    let fundingIntentID: PublicKey?
    let fromMint: PublicKey
    let toMint: PublicKey
    /// What the funding intent moves: the swap's recorded amount plus its fee, in `fromMint` quarks.
    let fundingQuarks: UInt64
}

/// The swap operations a collection payment's funding legs run, so the executor can be tested
/// without a network.
@MainActor
protocol CollectionSwapping: AnyObject {

    /// Starts `swap` under `swapID` (StartSwap) and funds it under `fundingIntentID` (SubmitIntent).
    func start(_ swap: CollectionFundingSwap, swapID: SwapId, fundingIntentID: PublicKey) async throws

    /// The owner's swaps that wait on their funding (GetPendingSwaps); empty when there are none.
    func pendingSwaps() async throws -> [PendingCollectionSwap]

    /// Funds `pending` under `fundingIntentID` (SubmitIntent) without starting it again, priced in
    /// `currency`.
    func fund(_ pending: PendingCollectionSwap, fundingIntentID: PublicKey, currency: CurrencyCode) async throws

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
        /// A swap failed or was refused, or its outcome couldn't be read.
        case failed
        /// A swap was started but hasn't settled. Its ids are kept, so a retry waits on it rather
        /// than starting another conversion that could land on top of it.
        case pending
    }

    /// How one leg ended.
    private enum LegResult {
        case settled
        case failed
        case pending
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
                switch await run(swap, source: leg.source, for: requestID) {
                case .settled: continue
                case .failed: return .failed
                case .pending: return .pending
                }
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

    /// What a leg does with the swap its kept ids name, once the server has been asked about it.
    private enum Resume {
        /// Start a swap under these ids: the kept ones when the server never saw the swap, fresh
        /// ones when it failed or was cancelled.
        case start(CollectionFundingStore.LegIDs)
        /// The swap is funded or running; wait on it without starting or funding it again.
        case wait
        case settled
        case pending
    }

    /// Runs one leg to a terminal state. Both ids are kept before its swap starts, so a retry finds
    /// that swap and never funds it under a second intent:
    /// - The server never saw it: start it again under both kept ids.
    /// - CREATED: don't start it again. Fund it under the funding id the server recorded, read from
    ///   GetPendingSwaps. One missing from that list is read again and handled by its new state.
    /// - FAILED or CANCELLED: its funds came back, so start a swap under fresh ids.
    /// - Any other state: it may still settle, so wait on it.
    private func run(_ swap: CollectionFundingSwap, source: String, for requestID: PaymentRequestID) async -> LegResult {
        let ids: CollectionFundingStore.LegIDs
        var start = true

        if let stored = store.legIDs(for: requestID, source: source) {
            let resume: Resume
            do {
                resume = try await self.resume(stored, currency: swap.amount.currency, source: source, for: requestID)
            } catch {
                // The outcome is unknown, so keep both ids: a retry asks the server about it first.
                return .failed
            }
            switch resume {
            case .start(let next):
                ids = next
            case .wait:
                ids = stored
                start = false
            case .settled:
                return .settled
            case .pending:
                return .pending
            }
        } else {
            ids = .generate()
        }

        if start {
            guard let fundingIntentID = ids.fundingIntentID else { return .failed }
            store.setLegIDs(ids, for: requestID, source: source)
            do {
                try await swapper.start(swap, swapID: ids.swapID, fundingIntentID: fundingIntentID)
            } catch {
                // The outcome is unknown, so keep both ids: a retry asks the server about it first.
                return .failed
            }
        }

        let state: SwapState
        do {
            state = try await swapper.waitForTerminalState(of: ids.swapID)
        } catch {
            return .failed
        }
        switch state {
        case .finalized:
            store.removeSwapID(for: requestID, source: source)
            return .settled
        case .failed, .cancelled:
            store.removeSwapID(for: requestID, source: source)
            return .failed
        case .unknown, .created, .funding, .funded, .submitting, .cancelling:
            // Not settled in time; keep both ids for the retry.
            return .pending
        }
    }

    /// Asks the server about the swap `stored` names and decides what the leg does with it.
    private func resume(
        _ stored: CollectionFundingStore.LegIDs,
        currency: CurrencyCode,
        source: String,
        for requestID: PaymentRequestID
    ) async throws -> Resume {
        var state = try await swapper.state(of: stored.swapID)

        if state == .created {
            if let pending = try await swapper.pendingSwaps().first(where: { $0.swapID == stored.swapID }) {
                // Fund it under the id the server recorded, which a leg stored before funding ids
                // were kept doesn't have locally.
                guard let fundingIntentID = pending.fundingIntentID else { return .pending }
                try await swapper.fund(pending, fundingIntentID: fundingIntentID, currency: currency)
                return .wait
            }
            // Not waiting on funding any more, so its funding may have landed since: read it again.
            state = try await swapper.state(of: stored.swapID)
        }

        switch state {
        case nil:
            // The server never saw it: start it again under the same ids.
            let ids = stored.withFundingIntentID()
            store.setLegIDs(ids, for: requestID, source: source)
            return .start(ids)
        case .created?:
            // Still unfunded but not listed as pending; leave it for the next retry.
            return .pending
        case .finalized?:
            // It landed before the last attempt ended; the plan this round was read before
            // balances caught up, so don't convert again.
            store.removeSwapID(for: requestID, source: source)
            return .settled
        case .failed?, .cancelled?:
            // Its funds came back; this attempt needs a swap of its own.
            store.removeSwapID(for: requestID, source: source)
            return .start(.generate())
        case .funding?, .funded?, .submitting?, .cancelling?, .unknown?:
            // It may still settle, so new ids could convert twice.
            return .wait
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

    func start(_ swap: CollectionFundingSwap, swapID: SwapId, fundingIntentID: PublicKey) async throws {
        guard let pin = await ratesController.currentPinnedState(for: swap.amount.currency, mint: swap.source),
              let amount = session.price(swap.amount, mint: swap.source, at: pin) else {
            throw Error.rateUnavailable
        }
        if swap.destination == .usdf {
            _ = try await session.sell(amount: amount, verifiedState: pin, in: swap.source, swapId: swapID, fundingIntentID: fundingIntentID)
        } else if swap.source == .usdf {
            _ = try await session.buy(amount: amount, feeAmount: nil, verifiedState: pin, of: swap.destination, swapId: swapID, fundingIntentID: fundingIntentID)
        } else {
            _ = try await session.buy(amount: amount, with: swap.source, verifiedState: pin, of: swap.destination, swapId: swapID, fundingIntentID: fundingIntentID)
        }
    }

    func pendingSwaps() async throws -> [PendingCollectionSwap] {
        try await session.pendingSwaps().map { metadata in
            let parameters = metadata.verifiedMetadata.clientParameters
            let fundingIntentID: PublicKey?
            if case .submitIntent(let id) = parameters.fundingSource {
                fundingIntentID = id
            } else {
                fundingIntentID = nil
            }
            return PendingCollectionSwap(
                swapID: metadata.swapId,
                fundingIntentID: fundingIntentID,
                fromMint: metadata.fromMint,
                toMint: metadata.toMint,
                fundingQuarks: parameters.amount.quarks + parameters.feeAmount.quarks
            )
        }
    }

    func fund(_ pending: PendingCollectionSwap, fundingIntentID: PublicKey, currency: CurrencyCode) async throws {
        guard let pin = await ratesController.currentPinnedState(for: currency, mint: pending.fromMint) else {
            throw Error.rateUnavailable
        }
        try await session.fundCreatedSwap(
            swapId: pending.swapID,
            fundingIntentID: fundingIntentID,
            quarks: pending.fundingQuarks,
            from: pending.fromMint,
            to: pending.toMint,
            verifiedState: pin
        )
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
