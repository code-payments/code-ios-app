//
//  CoinbaseFundingOperationTests.swift
//  FlipcashTests
//

import Foundation
import Testing
@testable import Flipcash
import FlipcashCore

@Suite("CoinbaseFundingOperation") @MainActor
struct CoinbaseFundingOperationTests {

    // MARK: - Buy

    @Test("Buy happy path creates an order, records the swap, awaits Apple Pay success")
    func buyHappyPath() async throws {
        let env = Env()
        let resolvedSwapId = SwapId.generate()
        env.session.buyWithCoinbaseOnrampHandler = { _, _, _ in resolvedSwapId }

        let payment = PaymentOperation.buy(.fixture())
        async let result = env.op.start(payment)

        try await waitUntil(env.op) { $0.state == .awaitingExternal(.applePay) }
        env.coinbaseService.receiveApplePayEvent(.fixture(.pollingSuccess))

        let swap = try await result
        #expect(swap.swapId == resolvedSwapId)
        #expect(swap.swapType == .buyWithCoinbase)
        #expect(swap.launchedMint == nil)
        #expect(env.session.launchCurrencyCalls.isEmpty)
        #expect(env.ordering.createOrderCalls.count == 1)
        #expect(env.op.state == .idle)
    }

    // MARK: - Launch

    @Test("Launch happy path preflights launchCurrency, then runs the same Apple Pay flow")
    func launchHappyPath() async throws {
        let env = Env()
        let mintedKey = PublicKey.jeffy
        let resolvedSwapId = SwapId.generate()
        env.session.launchCurrencyHandler = { _ in mintedKey }
        env.session.buyNewCurrencyWithCoinbaseOnrampHandler = { _, _, mint, _ in
            #expect(mint == mintedKey)
            return resolvedSwapId
        }

        let payment = PaymentOperation.launch(.fixture())
        async let result = env.op.start(payment)

        try await waitUntil(env.op) { $0.state == .awaitingExternal(.applePay) }
        #expect(env.op.launchedMint == mintedKey)
        env.coinbaseService.receiveApplePayEvent(.fixture(.pollingSuccess))

        let swap = try await result
        #expect(swap.swapId == resolvedSwapId)
        #expect(swap.swapType == .launchWithCoinbase)
        #expect(swap.launchedMint == mintedKey)
        #expect(env.session.launchCurrencyCalls.count == 1)
    }

    @Test("Cancel after launchCurrency succeeds preserves launchedMint for retry")
    func launch_cancelAfterLaunchSucceeds_preservesLaunchedMint() async throws {
        let env = Env()
        let mintedKey = PublicKey.jeffy
        env.session.launchCurrencyHandler = { _ in mintedKey }
        env.session.buyNewCurrencyWithCoinbaseOnrampHandler = { _, _, _, _ in .generate() }

        let payment = PaymentOperation.launch(.fixture())
        let task = Task { try await env.op.start(payment) }

        // Wait for launchCurrency to have run and the op to reach the Apple
        // Pay step — `launchedMint` is set during preflight.
        try await waitUntil(env.op) { $0.state == .awaitingExternal(.applePay) }
        #expect(env.op.launchedMint == mintedKey)

        env.op.cancel()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        // The mint must survive the cancel so the wizard can pass it back as
        // `preLaunchedMint` on the user's retry — without this, the retry
        // re-runs launchCurrency and the server returns `nameExists`.
        #expect(env.op.launchedMint == mintedKey)
        #expect(env.op.state == .idle)
    }

    @Test("Launch with preLaunchedMint skips launchCurrency and reuses the prior mint")
    func launch_withPreLaunchedMint_skipsLaunchCurrency() async throws {
        let env = Env()
        let priorMint = PublicKey.jeffy
        let resolvedSwapId = SwapId.generate()
        env.session.buyNewCurrencyWithCoinbaseOnrampHandler = { _, _, mint, _ in
            #expect(mint == priorMint)
            return resolvedSwapId
        }

        let payment = PaymentOperation.launch(.fixture(preLaunchedMint: priorMint))
        async let result = env.op.start(payment)

        try await waitUntil(env.op) { $0.state == .awaitingExternal(.applePay) }
        #expect(env.op.launchedMint == priorMint)
        env.coinbaseService.receiveApplePayEvent(.fixture(.pollingSuccess))

        let swap = try await result
        #expect(swap.launchedMint == priorMint)
        #expect(swap.swapType == .launchWithCoinbase)
        #expect(env.session.launchCurrencyCalls.isEmpty, "launchCurrency must not run when preLaunchedMint is set")
    }

    @Test("Launch missing attestations throws serverRejected before reaching the order step")
    func launch_missingAttestations_throws() async {
        let env = Env()
        let payment = PaymentOperation.launch(.fixture(attestations: nil))

        await #expect(throws: FundingOperationError.serverRejected("Missing launch attestations")) {
            try await env.op.start(payment)
        }
        #expect(env.session.launchCurrencyCalls.isEmpty)
        #expect(env.ordering.createOrderCalls.isEmpty)
    }

    // MARK: - Requirements

    @Test("Profile without verified phone+email throws requirementUnsatisfied")
    func profileNotVerified_throws() async {
        let env = Env(profile: Profile(displayName: nil, phone: Phone?.none, email: nil))
        let payment = PaymentOperation.buy(.fixture())

        await #expect(throws: FundingOperationError.requirementUnsatisfied(.verifiedContact)) {
            try await env.op.start(payment)
        }
        #expect(env.ordering.createOrderCalls.isEmpty)
    }

    // MARK: - Apple Pay terminal events

    @Test(
        "Apple Pay terminal error events throw serverRejected carrying Coinbase's errorMessage",
        arguments: [
            (ApplePayEvent.Event.pollingError, "Card declined"),
            (ApplePayEvent.Event.commitError, "Auth failed"),
        ]
    )
    func applePayTerminalError_throwsServerRejected(event: ApplePayEvent.Event, message: String) async throws {
        let env = Env()
        env.session.buyWithCoinbaseOnrampHandler = { _, _, _ in .generate() }

        let payment = PaymentOperation.buy(.fixture())
        let task = Task { try await env.op.start(payment) }
        try await waitUntil(env.op) { $0.state == .awaitingExternal(.applePay) }
        env.coinbaseService.receiveApplePayEvent(.fixture(event, errorMessage: message))

        await #expect(throws: FundingOperationError.serverRejected(message)) {
            try await task.value
        }
        #expect(env.op.state == .idle)
    }

    @Test("cancelled event throws CancellationError")
    func cancelled_throwsCancellationError() async throws {
        let env = Env()
        env.session.buyWithCoinbaseOnrampHandler = { _, _, _ in .generate() }

        let payment = PaymentOperation.buy(.fixture())
        let task = Task { try await env.op.start(payment) }
        try await waitUntil(env.op) { $0.state == .awaitingExternal(.applePay) }
        env.coinbaseService.receiveApplePayEvent(.fixture(.cancelled))

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }

    // MARK: - createOrder failures

    @Test("createOrder throwing a generic error surfaces as serverRejected")
    func createOrder_genericError_throwsServerRejected() async {
        let env = Env()
        env.ordering.createOrderHandler = { _ in throw SentinelError.boom }
        let payment = PaymentOperation.buy(.fixture())

        await #expect(throws: FundingOperationError.self) {
            try await env.op.start(payment)
        }
    }

    @Test("createOrder throwing OnrampErrorResponse propagates the subtitle into serverRejected")
    func createOrder_onrampErrorResponse_propagatesSubtitle() async throws {
        let env = Env()
        let errorResponse = try OnrampErrorResponse.fixture(errorType: "ERROR_CODE_GUEST_INVALID_CARD")
        env.ordering.createOrderHandler = { _ in throw errorResponse }
        let payment = PaymentOperation.buy(.fixture())

        await #expect(throws: FundingOperationError.serverRejected(errorResponse.subtitle)) {
            try await env.op.start(payment)
        }
    }
}

// MARK: - Test environment

@MainActor
private struct Env {
    let session: MockSession
    let ordering: MockOnrampOrdering
    let coinbaseService: CoinbaseService
    let op: CoinbaseFundingOperation

    init(profile: Profile? = .verifiedFixture) {
        let session = MockSession(profile: profile)
        let ordering = MockOnrampOrdering()
        let coinbaseService = CoinbaseService(coinbase: ordering)
        self.session = session
        self.ordering = ordering
        self.coinbaseService = coinbaseService
        // Long timeout so the idle timer never fires during tests.
        self.op = CoinbaseFundingOperation(
            coinbaseService: coinbaseService,
            session: session,
            applePayIdleTimeout: .seconds(60)
        )
    }
}

private enum SentinelError: Error { case boom }
