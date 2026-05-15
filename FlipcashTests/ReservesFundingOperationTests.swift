//
//  ReservesFundingOperationTests.swift
//  FlipcashTests
//

import Foundation
import Testing
@testable import Flipcash
import FlipcashCore

@Suite("ReservesFundingOperation") @MainActor
struct ReservesFundingOperationTests {

    // MARK: - Buy

    @Test("Buy happy path returns StartedSwap with .buyWithReserves and no launchedMint")
    func buyHappyPath() async throws {
        let session = MockSession()
        let recordedSwapId = SwapId.generate()
        session.buyHandler = { _, _, _ in recordedSwapId }

        let op = ReservesFundingOperation(session: session)
        let payload = PaymentOperation.BuyPayload(
            mint: .jeffy,
            currencyName: "TestCoin",
            amount: .mockOne,
            verifiedState: .fresh()
        )

        let swap = try await op.start(.buy(payload))

        #expect(swap.swapId == recordedSwapId)
        #expect(swap.swapType == .buyWithReserves)
        #expect(swap.currencyName == "TestCoin")
        #expect(swap.launchedMint == nil)
        #expect(session.buyCalls.count == 1)
    }

    @Test("Buy thrown error propagates")
    func buy_thrownErrorPropagates() async {
        let session = MockSession()
        session.buyHandler = { _, _, _ in throw MockError.insufficient }

        let op = ReservesFundingOperation(session: session)
        let payload = PaymentOperation.BuyPayload(
            mint: .jeffy,
            currencyName: "TestCoin",
            amount: .mockOne,
            verifiedState: .fresh()
        )

        await #expect(throws: MockError.insufficient) {
            try await op.start(.buy(payload))
        }
    }

    // MARK: - Launch

    @Test("Launch happy path launches then buys, returns StartedSwap with .launchWithReserves and launchedMint")
    func launchHappyPath() async throws {
        let session = MockSession()
        let mintedKey = PublicKey.jeffy
        let recordedSwapId = SwapId.generate()
        session.launchCurrencyHandler = { _ in mintedKey }
        session.buyNewCurrencyHandler = { _, _, _, _, _ in recordedSwapId }

        let op = ReservesFundingOperation(session: session)
        let payload = PaymentOperation.LaunchPayload(
            currencyName: "NewCoin",
            total: .mockOne,
            launchAmount: .mockOne,
            launchFee: .mockOne,
            attestations: .testFixture,
            verifiedState: .fresh()
        )

        let swap = try await op.start(.launch(payload))

        #expect(swap.swapId == recordedSwapId)
        #expect(swap.swapType == .launchWithReserves)
        #expect(swap.currencyName == "NewCoin")
        #expect(swap.launchedMint == mintedKey)
        #expect(session.launchCurrencyCalls.count == 1)
        #expect(session.buyNewCurrencyCalls.count == 1)
        #expect(session.buyNewCurrencyCalls.first?.mint == mintedKey)
    }

    @Test("Launch without attestations throws serverRejected")
    func launch_missingAttestations_throws() async {
        let session = MockSession()
        let op = ReservesFundingOperation(session: session)
        let payload = PaymentOperation.LaunchPayload(
            currencyName: "NewCoin",
            total: .mockOne,
            launchAmount: .mockOne,
            launchFee: .mockOne,
            attestations: nil,
            verifiedState: .fresh()
        )

        await #expect(throws: FundingOperationError.self) {
            try await op.start(.launch(payload))
        }
        #expect(session.launchCurrencyCalls.isEmpty)
    }

    @Test("Launch without verifiedState throws serverRejected")
    func launch_missingVerifiedState_throws() async {
        let session = MockSession()
        let op = ReservesFundingOperation(session: session)
        let payload = PaymentOperation.LaunchPayload(
            currencyName: "NewCoin",
            total: .mockOne,
            launchAmount: .mockOne,
            launchFee: .mockOne,
            attestations: .testFixture,
            verifiedState: nil
        )

        await #expect(throws: FundingOperationError.self) {
            try await op.start(.launch(payload))
        }
        #expect(session.launchCurrencyCalls.isEmpty)
    }

    @Test("Launch propagates launchCurrency errors and skips buyNewCurrency")
    func launch_launchThrows_skipsBuy() async {
        let session = MockSession()
        session.launchCurrencyHandler = { _ in throw MockError.launchRejected }

        let op = ReservesFundingOperation(session: session)
        let payload = PaymentOperation.LaunchPayload(
            currencyName: "NewCoin",
            total: .mockOne,
            launchAmount: .mockOne,
            launchFee: .mockOne,
            attestations: .testFixture,
            verifiedState: .fresh()
        )

        await #expect(throws: MockError.launchRejected) {
            try await op.start(.launch(payload))
        }
        #expect(session.buyNewCurrencyCalls.isEmpty)
    }

    // MARK: - Cancel

    @Test("Cancel during start throws CancellationError")
    func cancel_throwsCancellationError() async {
        let session = MockSession()
        // Buy handler waits forever; cancel should interrupt it.
        session.buyHandler = { _, _, _ in
            try await Task.sleep(for: .seconds(60))
            return SwapId.generate()
        }

        let op = ReservesFundingOperation(session: session)
        let payload = PaymentOperation.BuyPayload(
            mint: .jeffy,
            currencyName: "TestCoin",
            amount: .mockOne,
            verifiedState: .fresh()
        )

        let task = Task { try await op.start(.buy(payload)) }
        try? await waitUntil(op) { $0.state == .working }
        op.cancel()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }

    // MARK: - iOS 17.0 existential observation regression

    @Test("State changes are observable through the any FundingOperation existential")
    func anyFundingOperation_existentialObservation() async throws {
        let session = MockSession()
        session.buyHandler = { _, _, _ in
            // Keep the operation parked in .working long enough to observe it.
            try await Task.sleep(for: .milliseconds(80))
            return SwapId.generate()
        }

        let concrete = ReservesFundingOperation(session: session)
        let existential: any FundingOperation = concrete

        #expect(existential.state == .idle)

        let payload = PaymentOperation.BuyPayload(
            mint: .jeffy,
            currencyName: "TestCoin",
            amount: .mockOne,
            verifiedState: .fresh()
        )
        let task = Task { try await existential.start(.buy(payload)) }

        try await waitUntil(concrete) { _ in existential.state == .working }

        _ = try await task.value
        #expect(existential.state == .idle)
    }
}

// MARK: - Fixtures

private enum MockError: Error, Equatable {
    case insufficient
    case launchRejected
}
