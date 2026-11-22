//
//  CollectionFundingExecutorTests.swift
//  FlipcashTests
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("Collection funding executor")
struct CollectionFundingExecutorTests {

    private let requestID = PaymentRequestID(data: Data([4]))
    private let jeffy = PublicKey.generate()!
    private let bogey = PublicKey.generate()!
    private var dollars: String { PublicKey.usdf.base58 }

    /// Records each call in order and answers from scripted states.
    @MainActor
    private final class FakeSwapper: CollectionSwapping {
        var events: [String] = []
        var started: [(swap: CollectionFundingSwap, ids: CollectionFundingStore.LegIDs)] = []
        var funded: [(pending: PendingCollectionSwap, fundingIntentID: PublicKey)] = []
        /// What `state(of:)` answers per swap id; missing means the server has no such swap.
        var serverStates: [SwapId: SwapState] = [:]
        /// What `pendingSwaps()` answers.
        var pending: [PendingCollectionSwap] = []
        /// Runs inside `pendingSwaps()`, after it answers, as the server moving on would.
        var afterPendingSwaps: () -> Void = {}
        /// What `waitForTerminalState` answers; `.finalized` when unset.
        var waitResult: SwapState = .finalized
        var startError: Error?
        var fundError: Error?
        var onRefresh: () -> Void = {}
        /// Calls that never answer and ignore cancellation, as a stalled stream does.
        var unanswered: Set<Call> = []

        enum Call { case start, fund, wait }

        private func hangIfUnanswered(_ call: Call) async {
            guard unanswered.contains(call) else { return }
            await Task { try? await Task.sleep(for: .seconds(60)) }.value
        }

        func start(_ swap: CollectionFundingSwap, swapID: SwapId, fundingIntentID: PublicKey) async throws {
            events.append("start \(swap.source.base58.prefix(4))")
            started.append((swap, .init(swapID: swapID, fundingIntentID: fundingIntentID)))
            await hangIfUnanswered(.start)
            if let startError { throw startError }
        }

        func pendingSwaps() async throws -> [PendingCollectionSwap] {
            events.append("pending")
            defer { afterPendingSwaps() }
            return pending
        }

        func fund(_ pending: PendingCollectionSwap, fundingIntentID: PublicKey, currency: CurrencyCode) async throws {
            events.append("fund")
            funded.append((pending, fundingIntentID))
            await hangIfUnanswered(.fund)
            if let fundError { throw fundError }
        }

        func state(of swapID: SwapId) async throws -> SwapState? {
            events.append("state")
            return serverStates[swapID]
        }

        func waitForTerminalState(of swapID: SwapId) async throws -> SwapState {
            events.append("wait")
            await hangIfUnanswered(.wait)
            return waitResult
        }

        func refreshBalances() async throws {
            events.append("refresh")
            refreshes += 1
            onRefresh()
        }

        /// Refreshes answered so far; the paying balance rises with each, so a swap's credit shows
        /// on the first read after it unless `quarks` says otherwise.
        private(set) var refreshes: UInt64 = 0
        var quarks: ((PublicKey) -> UInt64)?

        func balanceQuarks(of mint: PublicKey) -> UInt64 {
            quarks?(mint) ?? refreshes
        }
    }

    private struct TestError: Error {}

    private func makeStore() -> CollectionFundingStore {
        let suite = "CollectionFundingExecutorTests.\(UUID().uuidString)"
        return CollectionFundingStore(userID: UUID(), defaults: UserDefaults(suiteName: suite)!)
    }

    private func freshIDs() -> CollectionFundingStore.LegIDs {
        .init(swapID: .generate(), fundingIntentID: PublicKey.generate()!)
    }

    /// The pending listing of `swapID` from Jeffy into `to`, recording `fundingIntentID` as its funding.
    private func pendingSwap(_ swapID: SwapId, fundingIntentID: PublicKey?, to: PublicKey = .usdf) -> PendingCollectionSwap {
        PendingCollectionSwap(swapID: swapID, fundingIntentID: fundingIntentID, fromMint: jeffy, toMint: to, fundingQuarks: 6_000_000_000)
    }

    /// A store holding `value` under the key a leg out of Jeffy was kept under before destinations
    /// were stored.
    private func legacyStore(_ value: Data) -> CollectionFundingStore {
        let defaults = UserDefaults(suiteName: "CollectionFundingLegacy.\(UUID().uuidString)")!
        let userID = UUID()
        let key = "\(requestID.data.hexEncodedString())|\(jeffy.base58)"
        defaults.set([key: value], forKey: "collectionFunding.swapIDs.\(userID.uuidString)")
        return CollectionFundingStore(userID: userID, defaults: defaults)
    }

    private func balance(_ mint: PublicKey, _ micros: Int64, fee: Int64 = 0) -> CollectionFundingBalance {
        CollectionFundingBalance(id: mint.base58, fiatMicros: micros, sellFeeBps: fee)
    }

    /// A $10 plan paying in `paying`.
    private func plan(paying: PublicKey, _ balances: [CollectionFundingBalance]) -> CollectionFundingPlan? {
        try? planCollectionFunding(
            amountMicros: 10_000_000,
            minorDigits: 2,
            minimumTopUpMicros: 0,
            selected: paying.base58,
            lastPaid: nil,
            dollars: dollars,
            balances: balances
        )
    }

    @Test("Each leg is submitted and settles before the next starts; balances reload after the round")
    func legOrder() async {
        let swapper = FakeSwapper()
        var balances = [balance(.usdf, 2_000_000), balance(jeffy, 0), balance(bogey, 9_000_000, fee: 100)]
        swapper.onRefresh = { balances = [self.balance(.usdf, 0), self.balance(self.jeffy, 10_000_000), self.balance(self.bogey, 1_000_000, fee: 100)] }
        let executor = CollectionFundingExecutor(swapper: swapper, store: makeStore())

        let outcome = await executor.fund(requestID, currency: .usd) { plan(paying: jeffy, balances) }

        #expect(outcome == .funded)
        #expect(swapper.events == ["start \(dollars.prefix(4))", "wait", "start \(bogey.base58.prefix(4))", "wait", "refresh"])
        #expect(swapper.started.map(\.swap.destination) == [jeffy, jeffy])
        #expect(swapper.started[0].swap.amount == FiatAmount(value: 2, currency: .usd))
    }

    @Test("The paying currency already covering the amount runs no swap")
    func noConversion() async {
        let swapper = FakeSwapper()
        let executor = CollectionFundingExecutor(swapper: swapper, store: makeStore())

        let outcome = await executor.fund(requestID, currency: .usd) {
            plan(paying: .usdf, [balance(.usdf, 12_000_000), balance(jeffy, 5_000_000)])
        }

        #expect(outcome == .funded)
        #expect(swapper.events.isEmpty)
    }

    @Test("A shortfall conversions can't cover runs no swap and reads as short")
    func uncoverable() async {
        let swapper = FakeSwapper()
        let executor = CollectionFundingExecutor(swapper: swapper, store: makeStore())

        let outcome = await executor.fund(requestID, currency: .usd) {
            plan(paying: .usdf, [balance(.usdf, 3_000_000), balance(jeffy, 2_000_000)])
        }

        #expect(outcome == .short)
        #expect(swapper.events.isEmpty)
    }

    @Test("A leg that lands short leaves a remainder the next round converts")
    func replanAfterShortLeg() async {
        let swapper = FakeSwapper()
        var balances = [balance(.usdf, 4_000_000), balance(jeffy, 20_000_000)]
        var refreshes = 0
        swapper.onRefresh = {
            refreshes += 1
            // The first sale delivered $5.90 of the $6.00 planned; the second covers the rest.
            balances = refreshes == 1
                ? [self.balance(.usdf, 9_900_000), self.balance(self.jeffy, 14_000_000)]
                : [self.balance(.usdf, 10_000_000), self.balance(self.jeffy, 13_900_000)]
        }
        let executor = CollectionFundingExecutor(swapper: swapper, store: makeStore())

        let outcome = await executor.fund(requestID, currency: .usd) { plan(paying: .usdf, balances) }

        #expect(outcome == .funded)
        #expect(swapper.started.count == 2)
        #expect(swapper.started[0].swap.amount == FiatAmount(value: 6, currency: .usd))
        #expect(swapper.started[1].swap.amount == FiatAmount(value: Decimal(string: "0.1")!, currency: .usd))
        #expect(swapper.started[0].ids.swapID != swapper.started[1].ids.swapID)
        #expect(swapper.started[0].ids.fundingIntentID != swapper.started[1].ids.fundingIntentID)
    }

    @Test("Two swaps in one round: a rise from the first credit alone doesn't end the wait; it ends once the plan is payable")
    func twoLegsOneCreditLate() async {
        let swapper = FakeSwapper()
        var balances = [balance(.usdf, 2_000_000), balance(jeffy, 0), balance(bogey, 9_000_000, fee: 100)]
        swapper.onRefresh = {
            if swapper.refreshes == 1 {
                // The Dollars' credit shows; the second swap's hasn't yet.
                balances = [self.balance(.usdf, 0), self.balance(self.jeffy, 2_000_000), self.balance(self.bogey, 1_000_000, fee: 100)]
            } else {
                balances = [self.balance(.usdf, 0), self.balance(self.jeffy, 10_000_000), self.balance(self.bogey, 1_000_000, fee: 100)]
            }
        }
        let executor = CollectionFundingExecutor(swapper: swapper, store: makeStore(), deliveryInterval: .zero)

        let outcome = await executor.fund(requestID, currency: .usd) { plan(paying: jeffy, balances) }

        #expect(outcome == .funded)
        #expect(swapper.events == ["start \(dollars.prefix(4))", "wait", "start \(bogey.base58.prefix(4))", "wait", "refresh", "refresh"])
        #expect(swapper.started.count == 2)
    }

    @Test("A credit that never shows stops the run as pending after every read, starting nothing more")
    func creditNeverShows() async {
        let swapper = FakeSwapper()
        swapper.quarks = { _ in 5 }
        let executor = CollectionFundingExecutor(swapper: swapper, store: makeStore(), deliveryInterval: .zero)

        let outcome = await executor.fund(requestID, currency: .usd) {
            plan(paying: .usdf, [balance(.usdf, 4_000_000), balance(jeffy, 20_000_000)])
        }

        #expect(outcome == .pending)
        #expect(swapper.started.count == 1)
        #expect(swapper.refreshes == UInt64(CollectionFundingExecutor.deliveryChecks))
    }

    @Test("Rounds stop at the cap as pending, since the balances cover the plan and a top-up would add money twice")
    func roundCap() async {
        let swapper = FakeSwapper()
        let executor = CollectionFundingExecutor(swapper: swapper, store: makeStore())

        // Balances never move, so every round plans the same leg again.
        let outcome = await executor.fund(requestID, currency: .usd) {
            plan(paying: .usdf, [balance(.usdf, 4_000_000), balance(jeffy, 20_000_000)])
        }

        #expect(outcome == .pending)
        #expect(swapper.started.count == CollectionFundingExecutor.maxRounds)
    }

    @Test("Both ids are kept before the swap starts")
    func idsKeptBeforeStart() async {
        let store = makeStore()
        let swapper = FakeSwapper()
        swapper.waitResult = .submitting
        let executor = CollectionFundingExecutor(swapper: swapper, store: store)

        _ = await executor.fund(requestID, currency: .usd) {
            plan(paying: .usdf, [balance(.usdf, 4_000_000), balance(jeffy, 20_000_000)])
        }

        let ids = store.legIDs(for: requestID, source: jeffy.base58, destination: dollars)
        #expect(ids?.fundingIntentID != nil)
        #expect(ids == swapper.started.first?.ids)
    }

    @Test("A retry starts a swap the server never saw under both kept ids")
    func retryStartsUnseenUnderKeptIDs() async {
        let store = makeStore()
        let stored = freshIDs()
        store.setLegIDs(stored, for: requestID, source: jeffy.base58, destination: dollars)
        let swapper = FakeSwapper()
        var balances = [balance(.usdf, 4_000_000), balance(jeffy, 20_000_000)]
        swapper.onRefresh = { balances = [self.balance(.usdf, 10_000_000), self.balance(self.jeffy, 14_000_000)] }
        let executor = CollectionFundingExecutor(swapper: swapper, store: store)

        let outcome = await executor.fund(requestID, currency: .usd) { plan(paying: .usdf, balances) }

        #expect(outcome == .funded)
        #expect(swapper.events == ["state", "start \(jeffy.base58.prefix(4))", "wait", "refresh"])
        #expect(swapper.started.map(\.ids) == [stored])
        #expect(store.swapID(for: requestID, source: jeffy.base58, destination: dollars) == nil)
    }

    @Test("A retry waits on a stored swap the server is still running and never starts it again")
    func retryWaitsOnRunningSwap() async {
        let store = makeStore()
        let stored = freshIDs()
        store.setLegIDs(stored, for: requestID, source: jeffy.base58, destination: dollars)
        let swapper = FakeSwapper()
        swapper.serverStates[stored.swapID] = .submitting
        var balances = [balance(.usdf, 4_000_000), balance(jeffy, 20_000_000)]
        swapper.onRefresh = { balances = [self.balance(.usdf, 10_000_000), self.balance(self.jeffy, 14_000_000)] }
        let executor = CollectionFundingExecutor(swapper: swapper, store: store)

        let outcome = await executor.fund(requestID, currency: .usd) { plan(paying: .usdf, balances) }

        #expect(outcome == .funded)
        #expect(swapper.events == ["state", "wait", "refresh"])
        #expect(swapper.started.isEmpty)
    }

    @Test("A retry whose stored swap already finalized converts nothing more for that leg")
    func retryFinalizedSwap() async {
        let store = makeStore()
        let stored = freshIDs()
        store.setLegIDs(stored, for: requestID, source: jeffy.base58, destination: dollars)
        let swapper = FakeSwapper()
        swapper.serverStates[stored.swapID] = .finalized
        var balances = [balance(.usdf, 4_000_000), balance(jeffy, 20_000_000)]
        swapper.onRefresh = { balances = [self.balance(.usdf, 10_000_000), self.balance(self.jeffy, 14_000_000)] }
        let executor = CollectionFundingExecutor(swapper: swapper, store: store)

        let outcome = await executor.fund(requestID, currency: .usd) { plan(paying: .usdf, balances) }

        #expect(outcome == .funded)
        #expect(swapper.events == ["state", "refresh"])
        #expect(store.swapID(for: requestID, source: jeffy.base58, destination: dollars) == nil)
    }

    @Test("A swap that fails ends funding and forgets its ids")
    func failedSwap() async {
        let store = makeStore()
        let swapper = FakeSwapper()
        swapper.waitResult = .failed
        let executor = CollectionFundingExecutor(swapper: swapper, store: store)

        let outcome = await executor.fund(requestID, currency: .usd) {
            plan(paying: .usdf, [balance(.usdf, 4_000_000), balance(jeffy, 20_000_000)])
        }

        #expect(outcome == .failed)
        #expect(!swapper.events.contains("refresh"))
        #expect(store.legIDs(for: requestID, source: jeffy.base58, destination: dollars) == nil)
    }

    @Test("A swap that doesn't settle in time stops on pending and keeps both ids for the retry")
    func unsettledSwap() async {
        let store = makeStore()
        let swapper = FakeSwapper()
        swapper.waitResult = .submitting
        let executor = CollectionFundingExecutor(swapper: swapper, store: store)

        let outcome = await executor.fund(requestID, currency: .usd) {
            plan(paying: .usdf, [balance(.usdf, 4_000_000), balance(jeffy, 20_000_000)])
        }

        #expect(outcome == .pending)
        #expect(!swapper.events.contains("refresh"))
        #expect(store.legIDs(for: requestID, source: jeffy.base58, destination: dollars) == swapper.started.first?.ids)
    }

    // MARK: - Stuck swaps

    /// A $10 Dollars plan funded from Jeffy, retried with `state` stored under the kept ids.
    private func retry(
        serverState state: SwapState?,
        stored: CollectionFundingStore.LegIDs? = nil,
        pending: (SwapId) -> [PendingCollectionSwap] = { _ in [] },
        afterPendingSwaps: ((FakeSwapper, SwapId) -> Void)? = nil,
        waitResult: SwapState = .finalized
    ) async -> (outcome: CollectionFundingExecutor.Outcome, swapper: FakeSwapper, store: CollectionFundingStore, stored: CollectionFundingStore.LegIDs) {
        let store = makeStore()
        let stored = stored ?? freshIDs()
        store.setLegIDs(stored, for: requestID, source: jeffy.base58, destination: dollars)
        let swapper = FakeSwapper()
        swapper.serverStates[stored.swapID] = state
        swapper.pending = pending(stored.swapID)
        if let afterPendingSwaps {
            swapper.afterPendingSwaps = { [unowned swapper] in afterPendingSwaps(swapper, stored.swapID) }
        }
        swapper.waitResult = waitResult
        var balances = [balance(.usdf, 4_000_000), balance(jeffy, 20_000_000)]
        swapper.onRefresh = { balances = [self.balance(.usdf, 10_000_000), self.balance(self.jeffy, 14_000_000)] }
        let executor = CollectionFundingExecutor(swapper: swapper, store: store)
        let outcome = await executor.fund(requestID, currency: .usd) { plan(paying: .usdf, balances) }
        return (outcome, swapper, store, stored)
    }

    @Test("A swap stuck in CREATED is funded under the funding id the server recorded and never started again")
    func createdFundsUnderRecordedID() async {
        let recorded = PublicKey.generate()!
        let r = await retry(serverState: .created, pending: { [self] in [pendingSwap(.generate(), fundingIntentID: nil), pendingSwap($0, fundingIntentID: recorded)] })

        #expect(r.outcome == .funded)
        #expect(r.swapper.events == ["state", "pending", "fund", "wait", "refresh"])
        #expect(r.swapper.started.isEmpty)
        #expect(r.swapper.funded.map(\.pending.swapID) == [r.stored.swapID])
        // The server's record wins over the id kept locally.
        #expect(r.stored.fundingIntentID != recorded)
        #expect(r.swapper.funded.map(\.fundingIntentID) == [recorded])
        #expect(r.swapper.funded.first?.pending.fundingQuarks == 6_000_000_000)
    }

    @Test("A CREATED swap kept before destinations were stored is never funded, and the leg starts under fresh ids")
    func createdLegacyEntryNotFunded() async {
        let legacy = freshIDs()
        let store = legacyStore(legacy.swapID.value + legacy.fundingIntentID!.data)
        let swapper = FakeSwapper()
        swapper.serverStates[legacy.swapID] = .created
        swapper.pending = [pendingSwap(legacy.swapID, fundingIntentID: legacy.fundingIntentID)]
        var balances = [balance(.usdf, 4_000_000), balance(jeffy, 20_000_000)]
        swapper.onRefresh = { balances = [self.balance(.usdf, 10_000_000), self.balance(self.jeffy, 14_000_000)] }
        let executor = CollectionFundingExecutor(swapper: swapper, store: store)

        let outcome = await executor.fund(requestID, currency: .usd) { plan(paying: .usdf, balances) }

        #expect(outcome == .funded)
        #expect(swapper.events == ["state", "start \(jeffy.base58.prefix(4))", "wait", "refresh"])
        #expect(swapper.funded.isEmpty)
        #expect(swapper.started.first?.ids.swapID != legacy.swapID)
        #expect(swapper.started.first?.ids.fundingIntentID != legacy.fundingIntentID)
        // Its funds never left Jeffy, so its ids stay until the payment clears them.
        #expect(store.keptLegs(for: requestID, source: jeffy.base58) == [.init(source: jeffy.base58, destination: nil, ids: legacy)])
    }

    @Test("A CREATED swap funded on retry that still hasn't settled stops on pending and keeps both ids")
    func createdFundedStillUnsettled() async {
        let r = await retry(serverState: .created, pending: { [self] in [pendingSwap($0, fundingIntentID: .generate()!)] }, waitResult: .funded)

        #expect(r.outcome == .pending)
        #expect(r.swapper.funded.count == 1)
        #expect(r.swapper.started.isEmpty)
        #expect(!r.swapper.events.contains("refresh"))
        #expect(r.store.legIDs(for: requestID, source: jeffy.base58, destination: dollars) == r.stored)
    }

    @Test("A CREATED swap whose recorded funding isn't an intent stops on pending")
    func createdWithoutIntentFunding() async {
        let r = await retry(serverState: .created, pending: { [self] in [pendingSwap($0, fundingIntentID: nil)] })

        #expect(r.outcome == .pending)
        #expect(r.swapper.events == ["state", "pending"])
        #expect(r.store.legIDs(for: requestID, source: jeffy.base58, destination: dollars) == r.stored)
    }

    @Test("A CREATED swap missing from the pending list is read again and waited on once running")
    func createdNotListedNowRunning() async {
        let r = await retry(serverState: .created, afterPendingSwaps: { swapper, id in swapper.serverStates[id] = .funding })

        #expect(r.outcome == .funded)
        #expect(r.swapper.events == ["state", "pending", "state", "wait", "refresh"])
        #expect(r.swapper.started.isEmpty)
        #expect(r.swapper.funded.isEmpty)
    }

    @Test("A CREATED swap missing from the pending list that failed meanwhile starts under fresh ids")
    func createdNotListedNowFailed() async {
        let r = await retry(serverState: .created, afterPendingSwaps: { swapper, id in swapper.serverStates[id] = .failed })

        #expect(r.outcome == .funded)
        #expect(r.swapper.events == ["state", "pending", "state", "start \(jeffy.base58.prefix(4))", "wait", "refresh"])
        #expect(r.swapper.started.first?.ids.swapID != r.stored.swapID)
        #expect(r.swapper.started.first?.ids.fundingIntentID != r.stored.fundingIntentID)
    }

    @Test("A CREATED swap missing from the pending list and still CREATED stops on pending, starting nothing")
    func createdNotListedStillCreated() async {
        let r = await retry(serverState: .created)

        #expect(r.outcome == .pending)
        #expect(r.swapper.events == ["state", "pending", "state"])
        #expect(r.store.legIDs(for: requestID, source: jeffy.base58, destination: dollars) == r.stored)
    }

    @Test("A retry gives a failed or cancelled swap fresh ids", arguments: [SwapState.failed, .cancelled])
    func retryFailedOrCancelledMintsFreshIDs(_ state: SwapState) async {
        let r = await retry(serverState: state)

        #expect(r.outcome == .funded)
        #expect(r.swapper.started.count == 1)
        #expect(r.swapper.started[0].ids.swapID != r.stored.swapID)
        #expect(r.swapper.started[0].ids.fundingIntentID != r.stored.fundingIntentID)
        #expect(r.swapper.started[0].ids.fundingIntentID != nil)
    }

    @Test("A retry waits on a swap the server is cancelling and mints no new ids")
    func retryWaitsOnCancelling() async {
        let r = await retry(serverState: .cancelling, waitResult: .cancelling)

        #expect(r.outcome == .pending)
        #expect(r.swapper.started.isEmpty)
        #expect(r.swapper.events == ["state", "wait"])
        #expect(r.store.legIDs(for: requestID, source: jeffy.base58, destination: dollars) == r.stored)
    }

    @Test("A swap the server reports in any running state is waited on, never started again", arguments: [SwapState.funding, .funded, .submitting, .unknown])
    func retryWaitsOnRunningStates(_ state: SwapState) async {
        let r = await retry(serverState: state)

        #expect(r.outcome == .funded)
        #expect(r.swapper.started.isEmpty)
        #expect(r.swapper.funded.isEmpty)
        #expect(r.swapper.events == ["state", "wait", "refresh"])
    }

    @Test("A cancelling swap that ends cancelled is forgotten, and a fresh plan starts its leg under fresh ids")
    func cancellingThenCancelled() async {
        let store = makeStore()
        let stored = freshIDs()
        store.setLegIDs(stored, for: requestID, source: jeffy.base58, destination: dollars)
        let swapper = FakeSwapper()
        swapper.serverStates[stored.swapID] = .cancelling
        swapper.waitResult = .cancelled
        var balances = [balance(.usdf, 4_000_000), balance(jeffy, 20_000_000)]
        swapper.onRefresh = { [unowned swapper] in
            // The cancelled swap's funds came back to Jeffy, so only the new swap adds Dollars.
            if swapper.started.isEmpty {
                swapper.waitResult = .finalized
            } else {
                balances = [self.balance(.usdf, 10_000_000), self.balance(self.jeffy, 14_000_000)]
            }
        }
        let executor = CollectionFundingExecutor(swapper: swapper, store: store)

        let outcome = await executor.fund(requestID, currency: .usd) { plan(paying: .usdf, balances) }

        #expect(outcome == .funded)
        #expect(swapper.events == ["state", "wait", "refresh", "start \(jeffy.base58.prefix(4))", "wait", "refresh"])
        #expect(swapper.started.first?.ids.swapID != stored.swapID)
        #expect(swapper.started.first?.ids.fundingIntentID != stored.fundingIntentID)
    }

    @Test("Attempts that never settle start one swap; later ones fund or wait on it and mint nothing")
    func neverMintsWhileUnsettled() async throws {
        let store = makeStore()
        let swapper = FakeSwapper()
        swapper.waitResult = .created
        let executor = CollectionFundingExecutor(swapper: swapper, store: store)
        let balances = [balance(.usdf, 4_000_000), balance(jeffy, 20_000_000)]

        #expect(await executor.fund(requestID, currency: .usd) { plan(paying: .usdf, balances) } == .pending)
        let first = try #require(swapper.started.first?.ids)
        swapper.serverStates[first.swapID] = .created
        swapper.pending = [pendingSwap(first.swapID, fundingIntentID: first.fundingIntentID)]
        #expect(await executor.fund(requestID, currency: .usd) { plan(paying: .usdf, balances) } == .pending)
        swapper.serverStates[first.swapID] = .submitting
        #expect(await executor.fund(requestID, currency: .usd) { plan(paying: .usdf, balances) } == .pending)

        #expect(swapper.started.map(\.ids) == [first])
        #expect(swapper.funded.map(\.fundingIntentID) == [first.fundingIntentID])
        #expect(store.legIDs(for: requestID, source: jeffy.base58, destination: dollars) == first)
    }

    @Test("A start that throws keeps both ids it recorded first")
    func startThrows() async {
        let store = makeStore()
        let swapper = FakeSwapper()
        swapper.startError = TestError()
        let executor = CollectionFundingExecutor(swapper: swapper, store: store)

        let outcome = await executor.fund(requestID, currency: .usd) {
            plan(paying: .usdf, [balance(.usdf, 4_000_000), balance(jeffy, 20_000_000)])
        }

        #expect(outcome == .failed)
        #expect(store.legIDs(for: requestID, source: jeffy.base58, destination: dollars) == swapper.started.first?.ids)
    }

    @Test("Funding a CREATED swap that throws keeps both ids and starts nothing")
    func fundThrows() async {
        let store = makeStore()
        let stored = freshIDs()
        store.setLegIDs(stored, for: requestID, source: jeffy.base58, destination: dollars)
        let swapper = FakeSwapper()
        swapper.serverStates[stored.swapID] = .created
        swapper.pending = [pendingSwap(stored.swapID, fundingIntentID: stored.fundingIntentID)]
        swapper.fundError = TestError()
        let executor = CollectionFundingExecutor(swapper: swapper, store: store)

        let outcome = await executor.fund(requestID, currency: .usd) {
            plan(paying: .usdf, [balance(.usdf, 4_000_000), balance(jeffy, 20_000_000)])
        }

        #expect(outcome == .failed)
        #expect(swapper.started.isEmpty)
        #expect(store.legIDs(for: requestID, source: jeffy.base58, destination: dollars) == stored)
    }

    // MARK: - Calls that never answer

    private let shortTimeout: Duration = .milliseconds(100)

    @Test("Each swap call gets 60 seconds")
    func callTimeoutIsSixtySeconds() {
        #expect(CollectionFundingExecutor.callTimeout == .seconds(60))
    }

    @Test("A start that never answers ends failed at the deadline and keeps both ids")
    func startNeverAnswers() async {
        let store = makeStore()
        let swapper = FakeSwapper()
        swapper.unanswered = [.start]
        let executor = CollectionFundingExecutor(swapper: swapper, store: store, timeout: shortTimeout)

        let outcome = await executor.fund(requestID, currency: .usd) {
            plan(paying: .usdf, [balance(.usdf, 4_000_000), balance(jeffy, 20_000_000)])
        }

        #expect(outcome == .failed)
        #expect(swapper.started.count == 1)
        #expect(!swapper.events.contains("wait"))
        #expect(store.legIDs(for: requestID, source: jeffy.base58, destination: dollars) == swapper.started.first?.ids)
    }

    @Test("A wait that never answers ends pending at the deadline and keeps both ids")
    func waitNeverAnswers() async {
        let store = makeStore()
        let swapper = FakeSwapper()
        swapper.unanswered = [.wait]
        let executor = CollectionFundingExecutor(swapper: swapper, store: store, timeout: shortTimeout)

        let outcome = await executor.fund(requestID, currency: .usd) {
            plan(paying: .usdf, [balance(.usdf, 4_000_000), balance(jeffy, 20_000_000)])
        }

        #expect(outcome == .pending)
        #expect(store.legIDs(for: requestID, source: jeffy.base58, destination: dollars) == swapper.started.first?.ids)
    }

    @Test("Funding a CREATED kept swap that never answers ends failed and keeps both ids")
    func keptFundingNeverAnswers() async {
        let store = makeStore()
        let stored = freshIDs()
        store.setLegIDs(stored, for: requestID, source: jeffy.base58, destination: dollars)
        let swapper = FakeSwapper()
        swapper.serverStates[stored.swapID] = .created
        swapper.pending = [pendingSwap(stored.swapID, fundingIntentID: stored.fundingIntentID)]
        swapper.unanswered = [.fund]
        let executor = CollectionFundingExecutor(swapper: swapper, store: store, timeout: shortTimeout)

        let settlement = await executor.settleKeptSwaps(for: requestID, currency: .usd)

        #expect(settlement == .failed)
        #expect(swapper.funded.count == 1)
        #expect(!swapper.events.contains("wait"))
        #expect(store.legIDs(for: requestID, source: jeffy.base58, destination: dollars) == stored)
    }

    @Test("A kept swap whose wait never answers settles as pending and keeps both ids")
    func keptWaitNeverAnswers() async {
        let store = makeStore()
        let stored = freshIDs()
        store.setLegIDs(stored, for: requestID, source: jeffy.base58, destination: dollars)
        let swapper = FakeSwapper()
        swapper.serverStates[stored.swapID] = .funding
        swapper.unanswered = [.wait]
        let executor = CollectionFundingExecutor(swapper: swapper, store: store, timeout: shortTimeout)

        let settlement = await executor.settleKeptSwaps(for: requestID, currency: .usd)

        #expect(settlement == .pending)
        #expect(!swapper.events.contains("refresh"))
        #expect(store.legIDs(for: requestID, source: jeffy.base58, destination: dollars) == stored)
    }

    // MARK: - Paying currency changed

    /// A $10 Dollars plan funded from Jeffy, retried with a swap kept from Jeffy into Bogey, as when
    /// the last attempt paid in Bogey. `state` is what the server reports for that swap.
    private func retryAfterSwitch(
        serverState state: SwapState?,
        waitResult: SwapState = .finalized
    ) async -> (outcome: CollectionFundingExecutor.Outcome, swapper: FakeSwapper, store: CollectionFundingStore, kept: CollectionFundingStore.LegIDs) {
        let store = makeStore()
        let kept = freshIDs()
        store.setLegIDs(kept, for: requestID, source: jeffy.base58, destination: bogey.base58)
        let swapper = FakeSwapper()
        swapper.serverStates[kept.swapID] = state
        swapper.pending = [pendingSwap(kept.swapID, fundingIntentID: kept.fundingIntentID, to: bogey)]
        swapper.waitResult = waitResult
        var balances = [balance(.usdf, 4_000_000), balance(jeffy, 20_000_000)]
        swapper.onRefresh = { [unowned swapper] in
            // A refresh after only the kept swap settled still leaves Dollars short.
            if !swapper.started.isEmpty {
                balances = [self.balance(.usdf, 10_000_000), self.balance(self.jeffy, 14_000_000)]
            }
        }
        let executor = CollectionFundingExecutor(swapper: swapper, store: store)
        let outcome = await executor.fund(requestID, currency: .usd) { plan(paying: .usdf, balances) }
        return (outcome, swapper, store, kept)
    }

    @Test("A swap kept for another paying currency, unfunded or never seen, is left alone and the new pair starts under fresh ids", arguments: [SwapState?.none, .created])
    func switchedPairLeavesUnfundedSwap(state: SwapState?) async {
        let r = await retryAfterSwitch(serverState: state)

        #expect(r.outcome == .funded)
        #expect(r.swapper.events == ["state", "start \(jeffy.base58.prefix(4))", "wait", "refresh"])
        #expect(r.swapper.funded.isEmpty)
        #expect(r.swapper.started.count == 1)
        #expect(r.swapper.started.first?.swap.destination == .usdf)
        #expect(r.swapper.started.first?.ids.swapID != r.kept.swapID)
        #expect(r.swapper.started.first?.ids.fundingIntentID != r.kept.fundingIntentID)
        // Kept for an attempt that pays in Bogey again.
        #expect(r.store.legIDs(for: requestID, source: jeffy.base58, destination: bogey.base58) == r.kept)
        #expect(r.store.legIDs(for: requestID, source: jeffy.base58, destination: dollars) == nil)
    }

    @Test("A swap kept for another paying currency that failed or was cancelled is forgotten and the new pair starts", arguments: [SwapState.failed, .cancelled])
    func switchedPairForgetsEndedSwap(state: SwapState) async {
        let r = await retryAfterSwitch(serverState: state)

        #expect(r.outcome == .funded)
        #expect(r.swapper.events == ["state", "start \(jeffy.base58.prefix(4))", "wait", "refresh"])
        #expect(r.swapper.started.first?.ids.swapID != r.kept.swapID)
        #expect(r.store.keptLegs(for: requestID, source: jeffy.base58).isEmpty)
    }

    @Test("A swap kept for another paying currency that is running is waited on; the new pair starts only after a fresh plan", arguments: [SwapState.funding, .submitting, .finalized])
    func switchedPairWaitsOnRunningSwap(state: SwapState) async {
        let r = await retryAfterSwitch(serverState: state)

        #expect(r.outcome == .funded)
        let waits = state == .finalized ? [] : ["wait"]
        #expect(r.swapper.events == ["state"] + waits + ["refresh", "start \(jeffy.base58.prefix(4))", "wait", "refresh"])
        #expect(r.swapper.funded.isEmpty)
        #expect(r.swapper.started.map(\.ids.swapID).contains(r.kept.swapID) == false)
        #expect(r.store.keptLegs(for: requestID, source: jeffy.base58).isEmpty)
    }

    @Test("A swap kept for another paying currency that doesn't settle in time stops on pending and starts nothing")
    func switchedPairStillRunning() async {
        let r = await retryAfterSwitch(serverState: .submitting, waitResult: .submitting)

        #expect(r.outcome == .pending)
        #expect(r.swapper.events == ["state", "wait"])
        #expect(r.swapper.started.isEmpty)
        #expect(r.store.legIDs(for: requestID, source: jeffy.base58, destination: bogey.base58) == r.kept)
    }

    @Test("Paying in a kept swap's currency again funds that swap, and leaves the one kept for another currency")
    func samePairFundsKeptSwap() async {
        let store = makeStore()
        let forDollars = freshIDs()
        let forBogey = freshIDs()
        store.setLegIDs(forDollars, for: requestID, source: jeffy.base58, destination: dollars)
        store.setLegIDs(forBogey, for: requestID, source: jeffy.base58, destination: bogey.base58)
        let swapper = FakeSwapper()
        swapper.serverStates[forDollars.swapID] = .created
        swapper.serverStates[forBogey.swapID] = .created
        swapper.pending = [
            pendingSwap(forBogey.swapID, fundingIntentID: forBogey.fundingIntentID, to: bogey),
            pendingSwap(forDollars.swapID, fundingIntentID: forDollars.fundingIntentID),
        ]
        var balances = [balance(.usdf, 4_000_000), balance(jeffy, 20_000_000)]
        swapper.onRefresh = { balances = [self.balance(.usdf, 10_000_000), self.balance(self.jeffy, 14_000_000)] }
        let executor = CollectionFundingExecutor(swapper: swapper, store: store)

        let outcome = await executor.fund(requestID, currency: .usd) { plan(paying: .usdf, balances) }

        #expect(outcome == .funded)
        #expect(swapper.events == ["state", "state", "pending", "fund", "wait", "refresh"])
        #expect(swapper.started.isEmpty)
        #expect(swapper.funded.map(\.pending.swapID) == [forDollars.swapID])
        #expect(store.legIDs(for: requestID, source: jeffy.base58, destination: dollars) == nil)
        #expect(store.legIDs(for: requestID, source: jeffy.base58, destination: bogey.base58) == forBogey)
    }

    // MARK: - Kept swaps from other sources

    /// A $10 Dollars plan funded from Jeffy, retried with a swap kept from Bogey into Dollars, as an
    /// attempt that drew on Bogey left it. `state` is what the server reports for that swap. Each
    /// plan read is logged as "plan".
    private func retryWithOtherSource(
        serverState state: SwapState,
        waitResult: SwapState = .finalized
    ) async -> (outcome: CollectionFundingExecutor.Outcome, swapper: FakeSwapper, store: CollectionFundingStore, kept: CollectionFundingStore.LegIDs) {
        let store = makeStore()
        let kept = freshIDs()
        store.setLegIDs(kept, for: requestID, source: bogey.base58, destination: dollars)
        let swapper = FakeSwapper()
        swapper.serverStates[kept.swapID] = state
        swapper.waitResult = waitResult
        var balances = [balance(.usdf, 4_000_000), balance(jeffy, 20_000_000)]
        swapper.onRefresh = { [unowned swapper] in
            // The Bogey swap lands $3 of Dollars; the Jeffy swap lands the rest.
            balances = swapper.started.isEmpty
                ? [self.balance(.usdf, 7_000_000), self.balance(self.jeffy, 20_000_000)]
                : [self.balance(.usdf, 10_000_000), self.balance(self.jeffy, 17_000_000)]
        }
        let executor = CollectionFundingExecutor(swapper: swapper, store: store)
        let outcome = await executor.fund(requestID, currency: .usd) {
            swapper.events.append("plan")
            return plan(paying: .usdf, balances)
        }
        return (outcome, swapper, store, kept)
    }

    @Test("A running swap kept from another source is waited on before the first plan is read")
    func otherSourceWaitedOnBeforePlanning() async {
        let r = await retryWithOtherSource(serverState: .submitting)

        #expect(r.outcome == .funded)
        #expect(r.swapper.events == ["state", "wait", "refresh", "plan", "start \(jeffy.base58.prefix(4))", "wait", "refresh", "plan"])
        // Planned once the Bogey swap landed, so Jeffy converts only what is still missing.
        #expect(r.swapper.started.map(\.swap.amount) == [FiatAmount(value: 3, currency: .usd)])
        #expect(r.swapper.started.first?.ids.swapID != r.kept.swapID)
        #expect(r.store.legIDs(for: requestID, source: bogey.base58, destination: dollars) == nil)
    }

    @Test("A swap kept from another source still running after the wait stops on pending before any plan")
    func otherSourceStillRunning() async {
        let r = await retryWithOtherSource(serverState: .submitting, waitResult: .submitting)

        #expect(r.outcome == .pending)
        #expect(r.swapper.events == ["state", "wait"])
        #expect(r.swapper.started.isEmpty)
        #expect(r.store.legIDs(for: requestID, source: bogey.base58, destination: dollars) == r.kept)
    }

    // MARK: - Settling kept swaps before a top-up

    /// Settles what a store holding `kept`, a swap from Jeffy into Dollars, came to, with the server
    /// reporting `state` for it and GetPendingSwaps listing `pending`.
    private func settleKept(
        serverState state: SwapState?,
        waitResult: SwapState = .finalized,
        kept: CollectionFundingStore.LegIDs? = nil,
        pending: [PendingCollectionSwap] = [],
        fundError: Error? = nil
    ) async -> (result: CollectionFundingExecutor.KeptSettlement, swapper: FakeSwapper, store: CollectionFundingStore, kept: CollectionFundingStore.LegIDs) {
        let store = makeStore()
        let kept = kept ?? freshIDs()
        store.setLegIDs(kept, for: requestID, source: jeffy.base58, destination: dollars)
        let swapper = FakeSwapper()
        swapper.serverStates[kept.swapID] = state
        swapper.waitResult = waitResult
        swapper.pending = pending
        swapper.fundError = fundError
        let result = await CollectionFundingExecutor(swapper: swapper, store: store).settleKeptSwaps(for: requestID, currency: .usd)
        return (result, swapper, store, kept)
    }

    @Test("Settling with no swap kept reads nothing")
    func settleNothingKept() async {
        let swapper = FakeSwapper()
        let result = await CollectionFundingExecutor(swapper: swapper, store: makeStore()).settleKeptSwaps(for: requestID, currency: .usd)

        #expect(result == .nothingKept)
        #expect(swapper.events.isEmpty)
    }

    @Test("Settling leaves a kept swap the server never saw kept and unstarted, and reads the balances")
    func settleLeavesUnseenKept() async {
        let r = await settleKept(serverState: nil)

        #expect(r.result == .settled)
        #expect(r.swapper.events == ["state", "refresh"])
        #expect(r.swapper.funded.isEmpty)
        #expect(r.swapper.started.isEmpty)
        #expect(r.store.legIDs(for: requestID, source: jeffy.base58, destination: dollars) == r.kept)
    }

    @Test("Settling funds a CREATED kept swap under the funding id the server recorded, waits for it to land, then forgets it and reads the balances")
    func settleFundsCreatedKept() async {
        let kept = freshIDs()
        let recorded = PublicKey.generate()!
        let r = await settleKept(serverState: .created, kept: kept, pending: [pendingSwap(kept.swapID, fundingIntentID: recorded)])

        #expect(r.result == .settled)
        #expect(r.swapper.events == ["state", "pending", "fund", "wait", "refresh"])
        #expect(r.swapper.funded.map(\.fundingIntentID) == [recorded])
        #expect(r.swapper.started.isEmpty)
        #expect(r.store.legIDs(for: requestID, source: jeffy.base58, destination: dollars) == nil)
    }

    @Test("Settling a CREATED kept swap that the server fails or cancels once funded forgets it and reads the balances its funds came back to", arguments: [SwapState.failed, .cancelled])
    func settleForgetsFundedCreatedThatEnds(_ ended: SwapState) async {
        let kept = freshIDs()
        let r = await settleKept(serverState: .created, waitResult: ended, kept: kept, pending: [pendingSwap(kept.swapID, fundingIntentID: kept.fundingIntentID)])

        #expect(r.result == .settled)
        #expect(r.swapper.events == ["state", "pending", "fund", "wait", "refresh"])
        #expect(r.swapper.started.isEmpty)
        #expect(r.store.legIDs(for: requestID, source: jeffy.base58, destination: dollars) == nil)
    }

    @Test("Settling a CREATED kept swap that is funded but hasn't settled by the end of the wait stops on pending, keeps its ids and reads no balances")
    func settleStopsOnFundedCreatedKept() async {
        let kept = freshIDs()
        let r = await settleKept(serverState: .created, waitResult: .funding, kept: kept, pending: [pendingSwap(kept.swapID, fundingIntentID: kept.fundingIntentID)])

        #expect(r.result == .pending)
        #expect(r.swapper.events == ["state", "pending", "fund", "wait"])
        #expect(r.store.legIDs(for: requestID, source: jeffy.base58, destination: dollars) == kept)
    }

    @Test("Settling a CREATED kept swap whose funding is refused fails, keeps its ids, and starts nothing")
    func settleFailsOnRefusedCreatedFunding() async {
        let kept = freshIDs()
        let r = await settleKept(serverState: .created, kept: kept, pending: [pendingSwap(kept.swapID, fundingIntentID: kept.fundingIntentID)], fundError: TestError())

        #expect(r.result == .failed)
        #expect(r.swapper.events == ["state", "pending", "fund"])
        #expect(r.swapper.started.isEmpty)
        #expect(r.store.legIDs(for: requestID, source: jeffy.base58, destination: dollars) == kept)
    }

    @Test("Settling a CREATED kept swap that GetPendingSwaps doesn't list with a funding id submits nothing and waits on it", arguments: [false, true])
    func settleWaitsOnUnlistedCreatedKept(listedWithoutFundingID: Bool) async {
        let kept = freshIDs()
        let pending = listedWithoutFundingID ? [pendingSwap(kept.swapID, fundingIntentID: nil)] : []
        let r = await settleKept(serverState: .created, kept: kept, pending: pending)

        #expect(r.result == .settled)
        #expect(r.swapper.events == ["state", "pending", "wait", "refresh"])
        #expect(r.swapper.funded.isEmpty)
        #expect(r.swapper.started.isEmpty)
        #expect(r.store.legIDs(for: requestID, source: jeffy.base58, destination: dollars) == nil)
    }

    @Test("Settling forgets a kept swap that already failed or was cancelled, and reads the balances its funds came back to", arguments: [SwapState.failed, .cancelled])
    func settleForgetsEndedKept(_ state: SwapState) async {
        let r = await settleKept(serverState: state)

        #expect(r.result == .settled)
        #expect(r.swapper.events == ["state", "refresh"])
        #expect(r.store.legIDs(for: requestID, source: jeffy.base58, destination: dollars) == nil)
    }

    @Test("Settling waits on a running kept swap, then forgets it and reads the balances it landed")
    func settleWaitsOnRunningKept() async {
        let r = await settleKept(serverState: .submitting)

        #expect(r.result == .settled)
        #expect(r.swapper.events == ["state", "wait", "refresh"])
        #expect(r.store.legIDs(for: requestID, source: jeffy.base58, destination: dollars) == nil)
    }

    @Test("Settling a kept swap still running after the wait stops on pending, keeps its ids and reads no balances")
    func settleStopsOnPendingKept() async {
        let r = await settleKept(serverState: .submitting, waitResult: .submitting)

        #expect(r.result == .pending)
        #expect(r.swapper.events == ["state", "wait"])
        #expect(r.store.legIDs(for: requestID, source: jeffy.base58, destination: dollars) == r.kept)
    }

    // MARK: - Store

    @Test("Kept ids survive a relaunch, and the next attempt starts under both")
    func idsSurviveRelaunch() async {
        let defaults = UserDefaults(suiteName: "CollectionFundingRelaunch.\(UUID().uuidString)")!
        let userID = UUID()
        let balances = [balance(.usdf, 4_000_000), balance(jeffy, 20_000_000)]

        let before = FakeSwapper()
        before.waitResult = .submitting
        let first = CollectionFundingExecutor(swapper: before, store: CollectionFundingStore(userID: userID, defaults: defaults))
        #expect(await first.fund(requestID, currency: .usd) { plan(paying: .usdf, balances) } == .pending)

        // A new launch: fresh store and executor over the same defaults, and a server that never
        // saw the swap, as when StartSwap died with the app.
        let after = FakeSwapper()
        after.waitResult = .submitting
        let relaunched = CollectionFundingStore(userID: userID, defaults: defaults)
        #expect(relaunched.legIDs(for: requestID, source: jeffy.base58, destination: dollars) == before.started.first?.ids)
        let second = CollectionFundingExecutor(swapper: after, store: relaunched)
        #expect(await second.fund(requestID, currency: .usd) { plan(paying: .usdf, balances) } == .pending)

        #expect(after.started.map(\.ids) == before.started.map(\.ids))
    }

    @Test("A leg stored as a bare swap id reads back with neither destination nor funding id, and is never started again")
    func legacyEntry() async throws {
        let swapID = SwapId.generate()
        let store = legacyStore(swapID.value)

        let legacy = CollectionFundingStore.KeptLeg(source: jeffy.base58, destination: nil, ids: .init(swapID: swapID, fundingIntentID: nil))
        #expect(store.keptLegs(for: requestID, source: jeffy.base58) == [legacy])
        #expect(store.legIDs(for: requestID, source: jeffy.base58, destination: dollars) == nil)

        let swapper = FakeSwapper()
        swapper.waitResult = .submitting
        let executor = CollectionFundingExecutor(swapper: swapper, store: store)
        _ = await executor.fund(requestID, currency: .usd) {
            plan(paying: .usdf, [balance(.usdf, 4_000_000), balance(jeffy, 20_000_000)])
        }

        let started = try #require(swapper.started.first?.ids)
        #expect(swapper.started.count == 1)
        #expect(started.swapID != swapID)
        #expect(started.fundingIntentID != nil)
        #expect(store.legIDs(for: requestID, source: jeffy.base58, destination: dollars) == started)
        #expect(store.keptLegs(for: requestID, source: jeffy.base58).contains(legacy))
    }

    @Test("Every leg kept for a request reads back with its pair, legacy ones included, in a fixed order")
    func keptLegsAcrossSources() {
        let legacy = freshIDs()
        let store = legacyStore(legacy.swapID.value + legacy.fundingIntentID!.data)
        let fromBogey = freshIDs()
        let fromJeffy = freshIDs()
        store.setLegIDs(fromJeffy, for: requestID, source: jeffy.base58, destination: dollars)
        store.setLegIDs(fromBogey, for: requestID, source: bogey.base58, destination: dollars)
        store.setLegIDs(freshIDs(), for: PaymentRequestID(data: Data([5])), source: jeffy.base58, destination: dollars)

        let expected: [CollectionFundingStore.KeptLeg] = [
            .init(source: bogey.base58, destination: dollars, ids: fromBogey),
            .init(source: jeffy.base58, destination: nil, ids: legacy),
            .init(source: jeffy.base58, destination: dollars, ids: fromJeffy),
        ].sorted { ($0.source, $0.destination ?? "") < ($1.source, $1.destination ?? "") }
        #expect(store.keptLegs(for: requestID) == expected)
    }

    @Test("Leg ids are kept per request and per user")
    func storeScoping() {
        let defaults = UserDefaults(suiteName: "CollectionFundingStoreScope.\(UUID().uuidString)")!
        let alice = CollectionFundingStore(userID: UUID(), defaults: defaults)
        let bob = CollectionFundingStore(userID: UUID(), defaults: defaults)
        let other = PaymentRequestID(data: Data([5]))
        let ids = freshIDs()

        alice.setLegIDs(ids, for: requestID, source: jeffy.base58, destination: dollars)
        alice.setLegIDs(ids, for: other, source: jeffy.base58, destination: dollars)
        alice.clearSwapIDs(for: requestID)

        #expect(alice.legIDs(for: requestID, source: jeffy.base58, destination: dollars) == nil)
        #expect(alice.legIDs(for: other, source: jeffy.base58, destination: dollars) == ids)
        #expect(bob.legIDs(for: other, source: jeffy.base58, destination: dollars) == nil)
    }
}
