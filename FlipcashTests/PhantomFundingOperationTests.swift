//
//  PhantomFundingOperationTests.swift
//  FlipcashTests
//

import Foundation
import Testing
@testable import Flipcash
import FlipcashCore

@Suite("PhantomFundingOperation") @MainActor
struct PhantomFundingOperationTests {

    // MARK: - Buy

    @Test("Buy happy path drives education → connect → confirm → sign and returns .buyWithPhantom")
    func buyHappyPath() async throws {
        let session = MockSession()
        let wallet = MockTransactionSigning()
        let rpc = MockSolanaRPC()
        let resolvedSwapId = SwapId.generate()
        session.buyWithExternalFundingHandler = { swapId, _, _, _ in
            // Server returns the same swap id the wallet embedded — that's
            // the unification the operation passes through.
            #expect(swapId == wallet.sendSignRequestCalls.first?.fundingSwapId)
            return resolvedSwapId
        }

        let op = PhantomFundingOperation(walletConnection: wallet, session: session, rpc: rpc)
        let payload = PaymentOperation.BuyPayload(
            mint: .jeffy,
            currencyName: "TestCoin",
            amount: .mockOne,
            verifiedState: .fresh()
        )

        async let result = op.start(.buy(payload))

        try await waitUntil(op) { state(of: $0).isEducation }
        op.confirm()

        // `.phantomConnect` may finish faster than our poll interval when
        // the handshake handler runs synchronously, so skip the transient
        // check and wait for the next user-action gate.
        try await waitUntil(op) { state(of: $0).isConfirm }
        op.confirm()

        try await waitUntil(op) { state(of: $0).isSigning }
        wallet.yieldDeeplinkEvent(.signed(Self.validSignedTransactionBase58))

        let swap = try await result
        #expect(swap.swapId == resolvedSwapId)
        #expect(swap.swapType == .buyWithPhantom)
        #expect(swap.launchedMint == nil)
        #expect(wallet.handshakeCallCount == 1)
        #expect(wallet.sendSignRequestCalls.count == 1)
        #expect(op.state == .idle)
    }

    // MARK: - Launch

    @Test("Launch happy path preflights launchCurrency, then drives the same flow as buy")
    func launchHappyPath() async throws {
        let session = MockSession()
        let wallet = MockTransactionSigning()
        let rpc = MockSolanaRPC()
        let mintedKey = PublicKey.jeffy
        let resolvedSwapId = SwapId.generate()
        session.launchCurrencyHandler = { _ in mintedKey }
        session.buyNewCurrencyWithExternalFundingHandler = { _, _, mint, _ in
            #expect(mint == mintedKey)
            return resolvedSwapId
        }

        let op = PhantomFundingOperation(walletConnection: wallet, session: session, rpc: rpc)
        let payload = PaymentOperation.LaunchPayload(
            currencyName: "NewCoin",
            total: .mockOne,
            launchAmount: .mockOne,
            launchFee: .mockOne,
            attestations: .testFixture
        )

        async let result = op.start(.launch(payload))

        try await waitUntil(op) { state(of: $0).isEducation }
        #expect(op.launchedMint == mintedKey)
        op.confirm()

        try await waitUntil(op) { state(of: $0).isConfirm }
        op.confirm()

        try await waitUntil(op) { state(of: $0).isSigning }
        wallet.yieldDeeplinkEvent(.signed(Self.validSignedTransactionBase58))

        let swap = try await result
        #expect(swap.swapType == .launchWithPhantom)
        #expect(swap.launchedMint == mintedKey)
        #expect(swap.swapId == resolvedSwapId)
    }

    // MARK: - Cancel + retry

    @Test("Cancel during education phase throws CancellationError")
    func cancel_duringEducation_throws() async throws {
        let op = PhantomFundingOperation(
            walletConnection: MockTransactionSigning(),
            session: MockSession(),
            rpc: MockSolanaRPC()
        )
        let payload = PaymentOperation.BuyPayload(
            mint: .jeffy,
            currencyName: "TestCoin",
            amount: .mockOne,
            verifiedState: .fresh()
        )

        let task = Task { try await op.start(.buy(payload)) }
        try await waitUntil(op) { state(of: $0).isEducation }
        op.cancel()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }

    @Test("Handshake userCancelledConnect loops back to .education and retries on next confirm")
    func handshakeUserCancelled_loopsBackToEducation() async throws {
        let wallet = MockTransactionSigning()
        let session = MockSession()
        let resolvedSwapId = SwapId.generate()
        session.buyWithExternalFundingHandler = { _, _, _, _ in resolvedSwapId }

        // First handshake call throws userCancelledConnect; subsequent calls
        // succeed.
        var handshakeAttempt = 0
        wallet.handshakeHandler = {
            handshakeAttempt += 1
            if handshakeAttempt == 1 {
                throw WalletConnectionError.userCancelledConnect
            }
        }

        let op = PhantomFundingOperation(
            walletConnection: wallet,
            session: session,
            rpc: MockSolanaRPC()
        )
        let payload = PaymentOperation.BuyPayload(
            mint: .jeffy,
            currencyName: "TestCoin",
            amount: .mockOne,
            verifiedState: .fresh()
        )

        async let result = op.start(.buy(payload))

        // First attempt — confirm, fail, land back on .education with a banner.
        try await waitUntil(op) { state(of: $0).isEducation }
        op.confirm()
        try await waitUntil(op) { state(of: $0).isEducation && $0.lastErrorMessage != nil }
        #expect(op.lastErrorMessage == "Connection cancelled in Phantom")

        // Retry — confirm clears the banner and re-runs handshake (now passes).
        op.confirm()
        #expect(op.lastErrorMessage == nil)

        try await waitUntil(op) { state(of: $0).isConfirm }
        op.confirm()
        try await waitUntil(op) { state(of: $0).isSigning }
        wallet.yieldDeeplinkEvent(.signed(Self.validSignedTransactionBase58))

        let swap = try await result
        #expect(swap.swapType == .buyWithPhantom)
        #expect(wallet.handshakeCallCount == 2)
    }

    @Test("Sign-step userCancelled loops back to .confirm and retries on next confirm")
    func signUserCancelled_loopsBackToConfirm() async throws {
        let wallet = MockTransactionSigning()
        let session = MockSession()
        let resolvedSwapId = SwapId.generate()
        session.buyWithExternalFundingHandler = { _, _, _, _ in resolvedSwapId }

        let op = PhantomFundingOperation(
            walletConnection: wallet,
            session: session,
            rpc: MockSolanaRPC()
        )
        let payload = PaymentOperation.BuyPayload(
            mint: .jeffy,
            currencyName: "TestCoin",
            amount: .mockOne,
            verifiedState: .fresh()
        )

        async let result = op.start(.buy(payload))

        try await waitUntil(op) { state(of: $0).isEducation }
        op.confirm()
        try await waitUntil(op) { state(of: $0).isConfirm }
        op.confirm()
        try await waitUntil(op) { state(of: $0).isSigning }
        wallet.yieldDeeplinkEvent(.userCancelled)

        // After a sign-cancel, we should land back on .confirm with a banner.
        try await waitUntil(op) { state(of: $0).isConfirm && $0.lastErrorMessage != nil }
        #expect(op.lastErrorMessage == "Transaction cancelled in Phantom")

        // Retry — confirm clears the banner, re-sends sign request,
        // success completes the flow.
        op.confirm()
        #expect(op.lastErrorMessage == nil)

        try await waitUntil(op) { state(of: $0).isSigning }
        wallet.yieldDeeplinkEvent(.signed(Self.validSignedTransactionBase58))

        let swap = try await result
        #expect(swap.swapType == .buyWithPhantom)
        #expect(wallet.sendSignRequestCalls.count == 2)
    }

    @Test("External cancel mid-retry-loop throws CancellationError (loop only catches user-cancel)")
    func externalCancel_breaksOutOfRetryLoop() async throws {
        let wallet = MockTransactionSigning()
        wallet.handshakeHandler = { throw WalletConnectionError.userCancelledConnect }

        let op = PhantomFundingOperation(
            walletConnection: wallet,
            session: MockSession(),
            rpc: MockSolanaRPC()
        )
        let payload = PaymentOperation.BuyPayload(
            mint: .jeffy,
            currencyName: "TestCoin",
            amount: .mockOne,
            verifiedState: .fresh()
        )

        let task = Task { try await op.start(.buy(payload)) }
        try await waitUntil(op) { state(of: $0).isEducation }
        op.confirm()

        // After cancel from Phantom, the operation loops back to .education
        // with an error message rather than throwing out.
        try await waitUntil(op) { state(of: $0).isEducation && $0.lastErrorMessage != nil }

        // External cancel (view back-swipe) breaks out of the loop with
        // CancellationError — distinct from the user-cancel that loops.
        op.cancel()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        // The cancel must short-circuit the loop — handshake should not
        // have run a second time, and `defer` should have reset state.
        #expect(wallet.handshakeCallCount == 1)
        #expect(op.state == .idle)
    }

    @Test("Cancel after launchCurrency succeeds preserves launchedMint for retry")
    func launch_cancelAfterLaunchSucceeds_preservesLaunchedMint() async throws {
        let session = MockSession()
        let wallet = MockTransactionSigning()
        let mintedKey = PublicKey.jeffy
        session.launchCurrencyHandler = { _ in mintedKey }

        let op = PhantomFundingOperation(walletConnection: wallet, session: session, rpc: MockSolanaRPC())
        let payload = PaymentOperation.LaunchPayload.fixture()

        let task = Task { try await op.start(.launch(payload)) }

        // Wait for launchCurrency to have run and the op to reach the
        // education prompt — `launchedMint` is set during preflight.
        try await waitUntil(op) { state(of: $0).isEducation }
        #expect(op.launchedMint == mintedKey)

        op.cancel()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        // The mint must survive the cancel so the wizard can pass it back as
        // `preLaunchedMint` on the user's retry — without this, the retry
        // re-runs launchCurrency and the server returns `nameExists`.
        #expect(op.launchedMint == mintedKey)
        #expect(op.state == .idle)
    }

    @Test("Launch with preLaunchedMint skips launchCurrency and reuses the prior mint")
    func launch_withPreLaunchedMint_skipsLaunchCurrency() async throws {
        let session = MockSession()
        let wallet = MockTransactionSigning()
        let priorMint = PublicKey.jeffy
        let resolvedSwapId = SwapId.generate()
        // launchCurrencyHandler is unset on purpose — if the op calls it the
        // mock throws `unimplemented`, which would fail the test below.
        session.buyNewCurrencyWithExternalFundingHandler = { _, _, mint, _ in
            #expect(mint == priorMint)
            return resolvedSwapId
        }

        let op = PhantomFundingOperation(walletConnection: wallet, session: session, rpc: MockSolanaRPC())
        let payload = PaymentOperation.LaunchPayload(
            currencyName: "NewCoin",
            total: .mockOne,
            launchAmount: .mockOne,
            launchFee: .mockOne,
            attestations: .testFixture,
            preLaunchedMint: priorMint
        )

        async let result = op.start(.launch(payload))

        try await waitUntil(op) { state(of: $0).isEducation }
        #expect(op.launchedMint == priorMint)
        op.confirm()
        try await waitUntil(op) { state(of: $0).isConfirm }
        op.confirm()
        try await waitUntil(op) { state(of: $0).isSigning }
        wallet.yieldDeeplinkEvent(.signed(Self.validSignedTransactionBase58))

        let swap = try await result
        #expect(swap.launchedMint == priorMint)
        #expect(swap.swapType == .launchWithPhantom)
        #expect(session.launchCurrencyCalls.isEmpty, "launchCurrency must not be called when preLaunchedMint is set")
    }

    @Test("Launch preflight error propagates and skips the rest of the flow")
    func launchPreflight_throws_skipsRest() async {
        let session = MockSession()
        session.launchCurrencyHandler = { _ in throw MockError.launchRejected }
        let wallet = MockTransactionSigning()

        let op = PhantomFundingOperation(
            walletConnection: wallet,
            session: session,
            rpc: MockSolanaRPC()
        )
        let payload = PaymentOperation.LaunchPayload(
            currencyName: "NewCoin",
            total: .mockOne,
            launchAmount: .mockOne,
            launchFee: .mockOne,
            attestations: .testFixture
        )

        await #expect(throws: MockError.launchRejected) {
            try await op.start(.launch(payload))
        }
        #expect(wallet.handshakeCallCount == 0)
        #expect(wallet.sendSignRequestCalls.isEmpty)
        #expect(op.launchedMint == nil)
        // `defer` must reset state even when the preflight short-circuits.
        #expect(op.state == .idle)
    }
}

// MARK: - Fixtures

private extension PhantomFundingOperationTests {

    /// Base58 encoding of a real SolanaTransaction so the operation's
    /// `SolanaTransaction(data:)` decode succeeds and we can drive through
    /// the simulate + submit steps using the default success-returning
    /// `MockSolanaRPC`.
    static let validSignedTransactionBase58: String = {
        let instructions = SwapInstructionBuilder.buildUsdcToUsdfSwapInstructions(
            sender: PublicKey.mock,
            owner: PublicKey.mock,
            amount: 1_000_000,
            pool: .usdf,
            swapId: PublicKey.mock
        )
        let tx = SolanaTransaction(
            payer: PublicKey.mock,
            recentBlockhash: Hash.mock,
            instructions: instructions
        )
        return Base58.fromBytes(Array(tx.encode()))
    }()
}

private enum MockError: Error, Equatable {
    case launchRejected
}

// MARK: - State helpers

private struct StateMatch {
    let isEducation: Bool
    let isConfirm: Bool
    let isConnecting: Bool
    let isSigning: Bool
}

@MainActor
private func state(of op: PhantomFundingOperation) -> StateMatch {
    switch op.state {
    case .awaitingUserAction(.education):
        return StateMatch(isEducation: true, isConfirm: false, isConnecting: false, isSigning: false)
    case .awaitingUserAction(.confirm):
        return StateMatch(isEducation: false, isConfirm: true, isConnecting: false, isSigning: false)
    case .awaitingExternal(.phantomConnect):
        return StateMatch(isEducation: false, isConfirm: false, isConnecting: true, isSigning: false)
    case .awaitingExternal(.phantomSign):
        return StateMatch(isEducation: false, isConfirm: false, isConnecting: false, isSigning: true)
    default:
        return StateMatch(isEducation: false, isConfirm: false, isConnecting: false, isSigning: false)
    }
}
