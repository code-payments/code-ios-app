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

    /// How long a swap's start, its funding or a wait on it gets before its outcome counts as
    /// unknown, so the pay sheet's lock always lifts.
    static let callTimeout: Duration = .seconds(60)

    private let swapper: any CollectionSwapping
    private let store: CollectionFundingStore
    private let timeout: Duration

    init(swapper: any CollectionSwapping, store: CollectionFundingStore, timeout: Duration = callTimeout) {
        self.swapper = swapper
        self.store = store
        self.timeout = timeout
    }

    /// Funds `requestID`'s payment. `plan` builds a plan from the current balances; it is called
    /// before the first round and after each one. Every swap an earlier attempt kept is settled
    /// before the first plan is read, so that plan sees what those swaps delivered.
    func fund(
        _ requestID: PaymentRequestID,
        currency: CurrencyCode,
        plan: () -> CollectionFundingPlan?
    ) async -> Outcome {
        let left: [SwapId: SwapState?]
        do {
            switch try await settleKept(for: requestID, fundingIn: nil) {
            case .pending:
                return .pending
            case .settled(let rest, let moved):
                left = rest
                if moved { try await swapper.refreshBalances() }
            }
        } catch {
            return .failed
        }

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
                switch await run(swap, source: leg.source, destination: paying.base58, for: requestID, left: left) {
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

    /// How settling the swaps earlier attempts kept ended.
    enum KeptSettlement: Equatable {
        /// No earlier attempt kept a swap, so nothing was read.
        case nothingKept
        /// None can still move funds, and the balances show what they delivered or returned.
        case settled
        /// One may still move funds; its ids stay.
        case pending
        /// A kept swap's state couldn't be read or its funding was refused, or the balances after
        /// it couldn't be read. Its ids stay.
        case failed
    }

    /// Settles every swap an earlier attempt kept for `requestID`, then reads the balances again
    /// when there was one, so a plan read next sees what those swaps delivered or returned. A swap
    /// the server holds unfunded is funded now, priced in `currency`, and waited on like any other.
    func settleKeptSwaps(for requestID: PaymentRequestID, currency: CurrencyCode) async -> KeptSettlement {
        guard !store.keptLegs(for: requestID).isEmpty else { return .nothingKept }
        do {
            switch try await settleKept(for: requestID, fundingIn: currency) {
            case .pending:
                return .pending
            case .settled:
                // Read even when nothing moved while waited on: a swap that had already failed or
                // been cancelled returned its funds, and the plan has to count them.
                try await swapper.refreshBalances()
                return .settled
            }
        } catch {
            return .failed
        }
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
    /// that swap and never funds it under a second intent. Only a swap kept for this leg's exact
    /// pair is resumed:
    /// - The server never saw it: start it again under both kept ids.
    /// - CREATED: don't start it again. Fund it under the funding id the server recorded, read from
    ///   GetPendingSwaps. One missing from that list is read again and handled by its new state.
    /// - FAILED or CANCELLED: its funds came back, so start a swap under fresh ids.
    /// - Any other state: it may still settle, so wait on it.
    /// `left` is what `settleKept` read of each kept swap it left in place; a leg whose kept swap
    /// is in it doesn't ask the server again. A swap kept for another pair, or stored before
    /// destinations were kept, was settled by `settleKept` and is never funded or started here.
    private func run(
        _ swap: CollectionFundingSwap,
        source: String,
        destination: String,
        for requestID: PaymentRequestID,
        left: [SwapId: SwapState?]
    ) async -> LegResult {
        let ids: CollectionFundingStore.LegIDs
        var start = true

        if let stored = store.legIDs(for: requestID, source: source, destination: destination) {
            let resume: Resume
            do {
                resume = try await self.resume(
                    stored,
                    known: left[stored.swapID],
                    currency: swap.amount.currency,
                    source: source,
                    destination: destination,
                    for: requestID
                )
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
            store.setLegIDs(ids, for: requestID, source: source, destination: destination)
            do {
                try await bounded { [swapper] in
                    try await swapper.start(swap, swapID: ids.swapID, fundingIntentID: fundingIntentID)
                }
            } catch {
                // The outcome is unknown, so keep both ids: a retry asks the server about it first.
                // A start left running past the deadline can't save a second swap under them.
                return .failed
            }
        }

        let state: SwapState
        do {
            state = try await waitBounded(ids.swapID)
        } catch {
            return .failed
        }
        switch state {
        case .finalized:
            store.removeSwapID(for: requestID, source: source, destination: destination)
            return .settled
        case .failed, .cancelled:
            store.removeSwapID(for: requestID, source: source, destination: destination)
            return .failed
        case .unknown, .created, .funding, .funded, .submitting, .cancelling:
            // Not settled in time; keep both ids for the retry.
            return .pending
        }
    }

    /// What the swaps earlier attempts kept came to.
    private enum Kept {
        /// None of them can still move funds. `left` holds what the server said of each swap whose
        /// ids stay: nil when it never saw the swap, CREATED when it holds it unfunded. `moved` is
        /// set when one landed or ended while waited on, so the balances are read again.
        case settled(left: [SwapId: SwapState?], moved: Bool)
        /// One may still move funds.
        case pending
    }

    /// Settles every swap kept for `requestID`, whatever pair it converts, before the first plan
    /// is read. A swap still converting would land on top of that plan's legs, or leave it reading
    /// balances from before the swap landed.
    /// - The server never saw it: nothing is on its way for it, and its kept ids hold no amount to
    ///   start it with. Its ids stay, so a leg for its pair starts it again under them.
    /// - CREATED, with `currency` nil: its funds haven't left the source. Its ids stay, so a leg
    ///   for its pair funds it rather than starting a second swap.
    /// - CREATED, with a `currency`: funded now under the funding id the server recorded, priced
    ///   in `currency`, then waited on. Nothing is submitted when GetPendingSwaps doesn't list it
    ///   with that id, and it is waited on all the same.
    /// - FAILED or CANCELLED: its funds came back. Its ids go.
    /// - FINALIZED, or reaching a terminal state while waited on: its ids go, and the balances are
    ///   read again before planning.
    /// - Not terminal by the end of the wait: it may still settle, so the payment stops on pending.
    private func settleKept(for requestID: PaymentRequestID, fundingIn currency: CurrencyCode?) async throws -> Kept {
        var left: [SwapId: SwapState?] = [:]
        var moved = false
        for kept in store.keptLegs(for: requestID) {
            let state: SwapState
            switch try await swapper.state(of: kept.ids.swapID) {
            case nil:
                left.updateValue(nil, forKey: kept.ids.swapID)
                continue
            case .created?:
                guard let currency else {
                    left[kept.ids.swapID] = .created
                    continue
                }
                _ = try await fundListed(kept.ids.swapID, currency: currency)
                state = try await waitBounded(kept.ids.swapID)
            case .failed?, .cancelled?:
                store.removeSwapID(for: requestID, source: kept.source, destination: kept.destination)
                continue
            case .finalized?:
                state = .finalized
            case .funding?, .funded?, .submitting?, .cancelling?, .unknown?:
                state = try await waitBounded(kept.ids.swapID)
            }
            switch state {
            case .finalized, .failed, .cancelled:
                store.removeSwapID(for: requestID, source: kept.source, destination: kept.destination)
                moved = true
            case .unknown, .created, .funding, .funded, .submitting, .cancelling:
                return .pending
            }
        }
        return .settled(left: left, moved: moved)
    }

    /// What asking GetPendingSwaps to fund a CREATED swap came to.
    private enum CreatedFunding {
        /// Its funding was submitted under the id the server recorded.
        case submitted
        /// It is listed with no funding intent id, so it is funded some other way.
        case noFundingID
        /// It isn't listed, so it has moved on since it was read as CREATED.
        case notListed
    }

    /// Funds `swapID`, read as CREATED, under the funding id GetPendingSwaps lists for it, which a
    /// leg stored before funding ids were kept doesn't have locally. The server moves a swap out of
    /// CREATED in the same commit that saves its funding, so one that reads CREATED was never funded.
    private func fundListed(_ swapID: SwapId, currency: CurrencyCode) async throws -> CreatedFunding {
        guard let pending = try await swapper.pendingSwaps().first(where: { $0.swapID == swapID }) else {
            return .notListed
        }
        guard let fundingIntentID = pending.fundingIntentID else { return .noFundingID }
        try await bounded { [swapper] in
            try await swapper.fund(pending, fundingIntentID: fundingIntentID, currency: currency)
        }
        return .submitted
    }

    /// Runs a swap call, throwing `CancellationError` once `timeout` passes, even when the call
    /// ignores cancellation, as the swap and intent streams do.
    private func bounded<T: Sendable>(_ call: @escaping @MainActor @Sendable () async throws -> T) async throws -> T {
        try await withDeadline(.now + timeout) { @MainActor in try await call() }
    }

    /// Waits on `swapID` until `timeout`. A wait that passes it reads as still converting, as one
    /// whose polls ran out does.
    private func waitBounded(_ swapID: SwapId) async throws -> SwapState {
        do {
            return try await bounded { [swapper] in try await swapper.waitForTerminalState(of: swapID) }
        } catch is CancellationError where !Task.isCancelled {
            return .unknown
        }
    }

    /// Decides what the leg does with the swap `stored` names. `known` is what `settleKept` read of
    /// it; when that is missing, the server is asked.
    private func resume(
        _ stored: CollectionFundingStore.LegIDs,
        known: SwapState??,
        currency: CurrencyCode,
        source: String,
        destination: String,
        for requestID: PaymentRequestID
    ) async throws -> Resume {
        var state: SwapState?
        if let known {
            state = known
        } else {
            state = try await swapper.state(of: stored.swapID)
        }

        if state == .created {
            switch try await fundListed(stored.swapID, currency: currency) {
            case .submitted:
                return .wait
            case .noFundingID:
                return .pending
            case .notListed:
                // Not waiting on funding any more, so its funding may have landed since: read it again.
                state = try await swapper.state(of: stored.swapID)
            }
        }

        switch state {
        case nil:
            // The server never saw it: start it again under the same ids.
            let ids = stored.withFundingIntentID()
            store.setLegIDs(ids, for: requestID, source: source, destination: destination)
            return .start(ids)
        case .created?:
            // Still unfunded but not listed as pending; leave it for the next retry.
            return .pending
        case .finalized?:
            // It landed before the last attempt ended; the plan this round was read before
            // balances caught up, so don't convert again.
            store.removeSwapID(for: requestID, source: source, destination: destination)
            return .settled
        case .failed?, .cancelled?:
            // Its funds came back; this attempt needs a swap of its own.
            store.removeSwapID(for: requestID, source: source, destination: destination)
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

    /// Polls at the inline swap cadence 120 times per leg: 30 seconds of sleeps plus one `GetSwap` call each.
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
