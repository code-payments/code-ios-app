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

    @Test("Buy happy path drives education → handshake → confirm → sign and returns .buyWithPhantom")
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

        try await waitUntil(op) { state(of: $0).isExternal }
        // handshake handler defaults to nil → completes immediately.

        try await waitUntil(op) { state(of: $0).isConfirm }
        op.confirm()

        try await waitUntil(op) { state(of: $0).isExternal }
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

        try await waitUntil(op) { state(of: $0).isExternal }
        wallet.yieldDeeplinkEvent(.signed(Self.validSignedTransactionBase58))

        let swap = try await result
        #expect(swap.swapType == .launchWithPhantom)
        #expect(swap.launchedMint == mintedKey)
        #expect(swap.swapId == resolvedSwapId)
    }

    // MARK: - Cancel + error

    @Test("Cancel during education phase throws CancellationError")
    func cancel_duringEducation_throws() async {
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
        try? await waitUntil(op) { state(of: $0).isEducation }
        op.cancel()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }

    @Test("Wallet userCancelled deeplink event throws CancellationError")
    func walletUserCancelled_throwsCancellationError() async throws {
        let wallet = MockTransactionSigning()
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
        try await waitUntil(op) { state(of: $0).isConfirm }
        op.confirm()
        try await waitUntil(op) { state(of: $0).isExternal }
        wallet.yieldDeeplinkEvent(.userCancelled)

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
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

private extension PaymentOperation.LaunchAttestations {
    static var testFixture: PaymentOperation.LaunchAttestations {
        PaymentOperation.LaunchAttestations(
            description: "Test description",
            billColors: ["#FFFFFF"],
            icon: Data([0x89, 0x50, 0x4E, 0x47]),
            nameAttestation: ModerationAttestation(rawValue: Data()),
            descriptionAttestation: ModerationAttestation(rawValue: Data()),
            iconAttestation: ModerationAttestation(rawValue: Data())
        )
    }
}

// MARK: - State helpers

private struct StateMatch {
    let isEducation: Bool
    let isConfirm: Bool
    let isExternal: Bool
}

@MainActor
private func state(of op: PhantomFundingOperation) -> StateMatch {
    switch op.state {
    case .awaitingUserAction(.education):
        return StateMatch(isEducation: true, isConfirm: false, isExternal: false)
    case .awaitingUserAction(.confirm):
        return StateMatch(isEducation: false, isConfirm: true, isExternal: false)
    case .awaitingExternal:
        return StateMatch(isEducation: false, isConfirm: false, isExternal: true)
    default:
        return StateMatch(isEducation: false, isConfirm: false, isExternal: false)
    }
}
