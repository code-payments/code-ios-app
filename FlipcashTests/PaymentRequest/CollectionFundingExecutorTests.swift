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
        var submitted: [(swap: CollectionFundingSwap, id: SwapId)] = []
        /// What `state(of:)` answers per swap id; missing means the server has no such swap.
        var serverStates: [SwapId: SwapState] = [:]
        /// What `waitForTerminalState` answers; `.finalized` when unset.
        var waitResult: SwapState = .finalized
        /// Answers for the first waits, in order, before `waitResult` takes over.
        var waitResults: [SwapState] = []
        var submitError: Error?
        var onRefresh: () -> Void = {}

        func submit(_ swap: CollectionFundingSwap, swapID: SwapId) async throws {
            events.append("submit \(swap.source.base58.prefix(4))")
            submitted.append((swap, swapID))
            if let submitError { throw submitError }
        }

        func state(of swapID: SwapId) async throws -> SwapState? {
            events.append("state")
            return serverStates[swapID]
        }

        func waitForTerminalState(of swapID: SwapId) async throws -> SwapState {
            events.append("wait")
            return waitResults.isEmpty ? waitResult : waitResults.removeFirst()
        }

        func refreshBalances() async throws {
            events.append("refresh")
            onRefresh()
        }
    }

    private struct TestError: Error {}

    private func makeStore() -> CollectionFundingStore {
        let suite = "CollectionFundingExecutorTests.\(UUID().uuidString)"
        return CollectionFundingStore(userID: UUID(), defaults: UserDefaults(suiteName: suite)!)
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
        #expect(swapper.events == ["submit \(dollars.prefix(4))", "wait", "submit \(bogey.base58.prefix(4))", "wait", "refresh"])
        #expect(swapper.submitted.map(\.swap.destination) == [jeffy, jeffy])
        #expect(swapper.submitted[0].swap.amount == FiatAmount(value: 2, currency: .usd))
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
        #expect(swapper.submitted.count == 2)
        #expect(swapper.submitted[0].swap.amount == FiatAmount(value: 6, currency: .usd))
        #expect(swapper.submitted[1].swap.amount == FiatAmount(value: Decimal(string: "0.1")!, currency: .usd))
        #expect(swapper.submitted[0].id != swapper.submitted[1].id)
    }

    @Test("Rounds stop at the cap and fall back to the short state")
    func roundCap() async {
        let swapper = FakeSwapper()
        let executor = CollectionFundingExecutor(swapper: swapper, store: makeStore())

        // Balances never move, so every round plans the same leg again.
        let outcome = await executor.fund(requestID, currency: .usd) {
            plan(paying: .usdf, [balance(.usdf, 4_000_000), balance(jeffy, 20_000_000)])
        }

        #expect(outcome == .short)
        #expect(swapper.submitted.count == CollectionFundingExecutor.maxRounds)
    }

    @Test("A retry reuses the stored swap id when the server has no record of it")
    func retryResubmitsSameID() async {
        let store = makeStore()
        let stored = SwapId.generate()
        store.setSwapID(stored, for: requestID, source: jeffy.base58)
        let swapper = FakeSwapper()
        var balances = [balance(.usdf, 4_000_000), balance(jeffy, 20_000_000)]
        swapper.onRefresh = { balances = [self.balance(.usdf, 10_000_000), self.balance(self.jeffy, 14_000_000)] }
        let executor = CollectionFundingExecutor(swapper: swapper, store: store)

        let outcome = await executor.fund(requestID, currency: .usd) { plan(paying: .usdf, balances) }

        #expect(outcome == .funded)
        #expect(swapper.events == ["state", "submit \(jeffy.base58.prefix(4))", "wait", "refresh"])
        #expect(swapper.submitted.map(\.id) == [stored])
        #expect(store.swapID(for: requestID, source: jeffy.base58) == nil)
    }

    @Test("A retry waits on a stored swap the server is still running and never submits it again")
    func retryWaitsOnRunningSwap() async {
        let store = makeStore()
        let stored = SwapId.generate()
        store.setSwapID(stored, for: requestID, source: jeffy.base58)
        let swapper = FakeSwapper()
        swapper.serverStates[stored] = .submitting
        var balances = [balance(.usdf, 4_000_000), balance(jeffy, 20_000_000)]
        swapper.onRefresh = { balances = [self.balance(.usdf, 10_000_000), self.balance(self.jeffy, 14_000_000)] }
        let executor = CollectionFundingExecutor(swapper: swapper, store: store)

        let outcome = await executor.fund(requestID, currency: .usd) { plan(paying: .usdf, balances) }

        #expect(outcome == .funded)
        #expect(swapper.events == ["state", "wait", "refresh"])
        #expect(swapper.submitted.isEmpty)
    }

    @Test("A retry whose stored swap already finalized converts nothing more for that leg")
    func retryFinalizedSwap() async {
        let store = makeStore()
        let stored = SwapId.generate()
        store.setSwapID(stored, for: requestID, source: jeffy.base58)
        let swapper = FakeSwapper()
        swapper.serverStates[stored] = .finalized
        var balances = [balance(.usdf, 4_000_000), balance(jeffy, 20_000_000)]
        swapper.onRefresh = { balances = [self.balance(.usdf, 10_000_000), self.balance(self.jeffy, 14_000_000)] }
        let executor = CollectionFundingExecutor(swapper: swapper, store: store)

        let outcome = await executor.fund(requestID, currency: .usd) { plan(paying: .usdf, balances) }

        #expect(outcome == .funded)
        #expect(swapper.events == ["state", "refresh"])
        #expect(store.swapID(for: requestID, source: jeffy.base58) == nil)
    }

    @Test("A retry whose stored swap failed starts a new swap under a new id")
    func retryFailedSwap() async {
        let store = makeStore()
        let stored = SwapId.generate()
        store.setSwapID(stored, for: requestID, source: jeffy.base58)
        let swapper = FakeSwapper()
        swapper.serverStates[stored] = .failed
        var balances = [balance(.usdf, 4_000_000), balance(jeffy, 20_000_000)]
        swapper.onRefresh = { balances = [self.balance(.usdf, 10_000_000), self.balance(self.jeffy, 14_000_000)] }
        let executor = CollectionFundingExecutor(swapper: swapper, store: store)

        let outcome = await executor.fund(requestID, currency: .usd) { plan(paying: .usdf, balances) }

        #expect(outcome == .funded)
        #expect(swapper.submitted.count == 1)
        #expect(swapper.submitted[0].id != stored)
    }

    @Test("A swap that fails ends funding and forgets its id")
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
        #expect(store.swapID(for: requestID, source: jeffy.base58) == nil)
    }

    @Test("A swap that doesn't settle in time stops on pending and keeps its id for the retry")
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
        #expect(store.swapID(for: requestID, source: jeffy.base58) == swapper.submitted.first?.id)
    }

    // MARK: - Stuck swaps

    /// A $10 Dollars plan funded from Jeffy, retried with `state` stored under the kept id.
    private func retry(
        serverState state: SwapState?,
        waitResult: SwapState = .finalized
    ) async -> (outcome: CollectionFundingExecutor.Outcome, swapper: FakeSwapper, store: CollectionFundingStore, stored: SwapId) {
        let store = makeStore()
        let stored = SwapId.generate()
        store.setSwapID(stored, for: requestID, source: jeffy.base58)
        let swapper = FakeSwapper()
        swapper.serverStates[stored] = state
        swapper.waitResult = waitResult
        var balances = [balance(.usdf, 4_000_000), balance(jeffy, 20_000_000)]
        swapper.onRefresh = { balances = [self.balance(.usdf, 10_000_000), self.balance(self.jeffy, 14_000_000)] }
        let executor = CollectionFundingExecutor(swapper: swapper, store: store)
        let outcome = await executor.fund(requestID, currency: .usd) { plan(paying: .usdf, balances) }
        return (outcome, swapper, store, stored)
    }

    @Test("A retry resubmits a swap stuck in CREATED under its kept id")
    func retryResubmitsCreated() async {
        let r = await retry(serverState: .created)

        #expect(r.outcome == .funded)
        #expect(r.swapper.events == ["state", "submit \(jeffy.base58.prefix(4))", "wait", "refresh"])
        #expect(r.swapper.submitted.map(\.id) == [r.stored])
    }

    @Test("A resubmitted swap that still hasn't settled stops on pending and keeps its id")
    func resubmittedStillUnsettled() async {
        let r = await retry(serverState: .created, waitResult: .created)

        #expect(r.outcome == .pending)
        #expect(r.swapper.submitted.map(\.id) == [r.stored])
        #expect(!r.swapper.events.contains("refresh"))
        #expect(r.store.swapID(for: requestID, source: jeffy.base58) == r.stored)
    }

    @Test("A retry gives a cancelled swap a fresh id, as it does a failed one")
    func retryCancelledSwap() async {
        let r = await retry(serverState: .cancelled)

        #expect(r.outcome == .funded)
        #expect(r.swapper.submitted.count == 1)
        #expect(r.swapper.submitted[0].id != r.stored)
    }

    @Test("A retry waits on a swap the server is cancelling and mints no new id")
    func retryWaitsOnCancelling() async {
        let r = await retry(serverState: .cancelling, waitResult: .cancelling)

        #expect(r.outcome == .pending)
        #expect(r.swapper.submitted.isEmpty)
        #expect(r.swapper.events == ["state", "wait"])
        #expect(r.store.swapID(for: requestID, source: jeffy.base58) == r.stored)
    }

    @Test("A swap the server reports in any running state is waited on, never resubmitted", arguments: [SwapState.funding, .funded, .submitting, .unknown])
    func retryWaitsOnRunningStates(_ state: SwapState) async {
        let r = await retry(serverState: state)

        #expect(r.outcome == .funded)
        #expect(r.swapper.submitted.isEmpty)
        #expect(r.swapper.events == ["state", "wait", "refresh"])
    }

    @Test("A cancelling swap that ends cancelled fails this attempt and frees the leg for a fresh id")
    func cancellingThenCancelled() async {
        let r = await retry(serverState: .cancelling, waitResult: .cancelled)

        #expect(r.outcome == .failed)
        #expect(r.swapper.submitted.isEmpty)
        #expect(r.store.swapID(for: requestID, source: jeffy.base58) == nil)
    }

    @Test("Attempts that never settle reuse the first id; no attempt mints another while it may settle")
    func neverMintsWhileUnsettled() async throws {
        let store = makeStore()
        let swapper = FakeSwapper()
        swapper.waitResult = .created
        let executor = CollectionFundingExecutor(swapper: swapper, store: store)
        let balances = [balance(.usdf, 4_000_000), balance(jeffy, 20_000_000)]

        #expect(await executor.fund(requestID, currency: .usd) { plan(paying: .usdf, balances) } == .pending)
        let first = try #require(swapper.submitted.first?.id)
        swapper.serverStates[first] = .created
        #expect(await executor.fund(requestID, currency: .usd) { plan(paying: .usdf, balances) } == .pending)
        swapper.serverStates[first] = .submitting
        #expect(await executor.fund(requestID, currency: .usd) { plan(paying: .usdf, balances) } == .pending)

        #expect(swapper.submitted.map(\.id) == [first, first])
        #expect(store.swapID(for: requestID, source: jeffy.base58) == first)
    }

    @Test("A submit that throws keeps the id it recorded first")
    func submitThrows() async {
        let store = makeStore()
        let swapper = FakeSwapper()
        swapper.submitError = TestError()
        let executor = CollectionFundingExecutor(swapper: swapper, store: store)

        let outcome = await executor.fund(requestID, currency: .usd) {
            plan(paying: .usdf, [balance(.usdf, 4_000_000), balance(jeffy, 20_000_000)])
        }

        #expect(outcome == .failed)
        #expect(store.swapID(for: requestID, source: jeffy.base58) == swapper.submitted.first?.id)
    }

    @Test("Swap ids are kept per request and per user")
    func storeScoping() {
        let defaults = UserDefaults(suiteName: "CollectionFundingStoreScope.\(UUID().uuidString)")!
        let alice = CollectionFundingStore(userID: UUID(), defaults: defaults)
        let bob = CollectionFundingStore(userID: UUID(), defaults: defaults)
        let other = PaymentRequestID(data: Data([5]))
        let id = SwapId.generate()

        alice.setSwapID(id, for: requestID, source: jeffy.base58)
        alice.setSwapID(id, for: other, source: jeffy.base58)
        alice.clearSwapIDs(for: requestID)

        #expect(alice.swapID(for: requestID, source: jeffy.base58) == nil)
        #expect(alice.swapID(for: other, source: jeffy.base58) == id)
        #expect(bob.swapID(for: other, source: jeffy.base58) == nil)
    }
}
