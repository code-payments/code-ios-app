//
//  PhantomCoordinatorTests.swift
//  FlipcashTests
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

/// Public-API coverage for `PhantomCoordinator`'s state machine. Tests that
/// drive the post-sign chain — simulation, server-notify, chain submit —
/// would require either yielding `DeeplinkEvent`s directly to the stream
/// (which crosses a `private` boundary on `WalletConnection`) or fabricating
/// fully-encrypted `transactionSigned` URLs. Both are deferred to a follow-up
/// that introduces protocol DI on the deeplink source.
@MainActor
@Suite("PhantomCoordinator — state machine")
struct PhantomCoordinatorTests {

    // MARK: - Fixtures

    private static func makeOperation() -> PaymentOperation {
        .buy(.init(
            mint: .usdc,
            currencyName: "USDC",
            amount: ExchangedFiat.compute(
                onChainAmount: TokenAmount(quarks: 1_000_000, mint: .usdc),
                rate: .oneToOne,
                supplyQuarks: nil
            ),
            verifiedState: .stale(bonded: false)
        ))
    }

    private static func makeLaunchOperation() -> PaymentOperation {
        let amount = ExchangedFiat.compute(
            onChainAmount: TokenAmount(quarks: 5_000_000, mint: .usdf),
            rate: .oneToOne,
            supplyQuarks: nil
        )
        return .launch(.init(
            currencyName: "Jeffy",
            total: amount,
            launchAmount: amount,
            launchFee: ExchangedFiat.compute(
                onChainAmount: .zero(mint: .usdf),
                rate: .oneToOne,
                supplyQuarks: nil
            )
        ))
    }

    private static func makeCoordinator() -> PhantomCoordinator {
        PhantomCoordinator(
            walletConnection: .mock,
            session: .mock,
            client: Container.mock.client
        )
    }

    // MARK: - State machine

    @Test("Initial state is .idle with no operation, no pending swap")
    func initial_isIdle() {
        let coordinator = Self.makeCoordinator()
        #expect(coordinator.state == .idle)
        #expect(coordinator.operation == nil)
        #expect(coordinator.isAwaitingExternalSwap == false)
        #expect(coordinator.processingState == .idle)
        #expect(coordinator.isProcessingCancelled == false)
    }

    @Test("start(_:) transitions to .connecting and captures the operation")
    func start_transitionsToConnecting() {
        let coordinator = Self.makeCoordinator()
        let operation = Self.makeOperation()

        coordinator.start(operation)

        #expect(coordinator.state == .connecting)
        #expect(coordinator.operation == operation)
    }

    @Test("start(.buy) clears a leftover launchHandler from a prior wizard flow")
    func start_buyClearsStaleLaunchHandler() {
        let coordinator = Self.makeCoordinator()
        coordinator.launchHandler = { _, _ in .buyExisting(swapId: .generate()) }

        coordinator.start(Self.makeOperation())

        #expect(coordinator.launchHandler == nil)
    }

    @Test("start(.launch) preserves a launchHandler set by the caller")
    func start_launchPreservesHandler() {
        let coordinator = Self.makeCoordinator()
        coordinator.launchHandler = { _, _ in .buyExisting(swapId: .generate()) }

        coordinator.start(Self.makeLaunchOperation())

        // Handler stays — the wizard sets it right before starting the
        // launch flow and the coordinator must invoke it after the user signs.
        #expect(coordinator.launchHandler != nil)
    }

    @Test("confirm() is a no-op outside .awaitingConfirm")
    func confirm_noOpFromWrongState() {
        let coordinator = Self.makeCoordinator()
        // No start() called — state is .idle.
        coordinator.confirm()
        #expect(coordinator.state == .idle)

        coordinator.start(Self.makeOperation())
        #expect(coordinator.state == .connecting)
        // Calling confirm during the connect handshake should not advance.
        coordinator.confirm()
        #expect(coordinator.state == .connecting)
    }

    @Test("cancel() resets pre-signing state to .idle")
    func cancel_resetsToIdle() {
        let coordinator = Self.makeCoordinator()
        coordinator.launchHandler = { _, _ in .buyExisting(swapId: .generate()) }
        coordinator.start(Self.makeLaunchOperation())

        coordinator.cancel()

        #expect(coordinator.state == .idle)
        #expect(coordinator.operation == nil)
        #expect(coordinator.launchHandler == nil)
        #expect(coordinator.isAwaitingExternalSwap == false)
    }

    @Test("dismissProcessing() clears processingState and pre-signing state")
    func dismissProcessing_resetsAll() {
        let coordinator = Self.makeCoordinator()
        coordinator.launchHandler = { _, _ in .buyExisting(swapId: .generate()) }
        coordinator.start(Self.makeLaunchOperation())

        coordinator.dismissProcessing()

        #expect(coordinator.state == .idle)
        #expect(coordinator.operation == nil)
        #expect(coordinator.launchHandler == nil)
        #expect(coordinator.processingState == .idle)
    }

    @Test("Setting processing = nil while idle is a no-op")
    func processing_nilWhileIdle_noOp() {
        let coordinator = Self.makeCoordinator()
        coordinator.processing = nil  // would crash if it tried to mutate
        #expect(coordinator.processingState == .idle)
        #expect(coordinator.processing == nil)
    }

    @Test("Setting launchProcessing = nil while idle is a no-op")
    func launchProcessing_nilWhileIdle_noOp() {
        let coordinator = Self.makeCoordinator()
        coordinator.launchProcessing = nil
        #expect(coordinator.processingState == .idle)
        #expect(coordinator.launchProcessing == nil)
    }

    @Test("isAwaitingExternalSwap is false when no pending swap")
    func isAwaitingExternalSwap_falseInitially() {
        let coordinator = Self.makeCoordinator()
        #expect(coordinator.isAwaitingExternalSwap == false)
        coordinator.start(Self.makeOperation())
        #expect(coordinator.isAwaitingExternalSwap == false)  // not until confirm
    }
}
