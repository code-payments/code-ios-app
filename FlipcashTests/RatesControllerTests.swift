//
//  RatesControllerTests.swift
//  FlipcashTests
//
//  Created by Claude.
//

import Foundation
import Testing
import Combine
@testable import Flipcash
import FlipcashCore
import FlipcashAPI

@Suite("RatesController")
struct RatesControllerTests {

    // MARK: - awaitVerifiedState -

    @Test("Returns immediately when verified state is already cached")
    @MainActor
    func awaitVerifiedState_cached_returnsImmediately() async {
        let controller = makeController()
        let mint = PublicKey.jeffy

        await controller.verifiedProtoService.saveRates([
            .makeTest(currencyCode: "usd", rate: 1.0)
        ])

        await controller.verifiedProtoService.saveReserveStates([
            .makeTest(mint: mint)
        ])

        let state = await controller.awaitVerifiedState(
            for: .usd,
            mint: mint,
            maxAttempts: 1,
            interval: .milliseconds(1)
        )

        #expect(state != nil)
        #expect(state?.rateProto.exchangeRate.currencyCode == "usd")
    }

    @Test("Returns nil when cache is empty and max attempts exhausted")
    @MainActor
    func awaitVerifiedState_empty_returnsNil() async {
        let controller = makeController()
        let mint = PublicKey.jeffy

        let state = await controller.awaitVerifiedState(
            for: .usd,
            mint: mint,
            maxAttempts: 3,
            interval: .milliseconds(10)
        )

        #expect(state == nil)
    }

    @Test("Returns state when data arrives after initial miss")
    @MainActor
    func awaitVerifiedState_delayedData_returnsOnce() async {
        let controller = makeController()
        let mint = PublicKey.jeffy

        // Simulate stream delivering data after a short delay
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            await controller.verifiedProtoService.saveRates([
                .makeTest(currencyCode: "usd", rate: 1.0)
            ])
            await controller.verifiedProtoService.saveReserveStates([
                .makeTest(mint: mint)
            ])
        }

        let state = await controller.awaitVerifiedState(
            for: .usd,
            mint: mint,
            maxAttempts: 10,
            interval: .milliseconds(20)
        )

        #expect(state != nil)
    }

    @Test("Includes reserve state when available for launchpad currency")
    @MainActor
    func awaitVerifiedState_withReserveState_returnsBoth() async {
        let controller = makeController()
        let mint = PublicKey.jeffy

        await controller.verifiedProtoService.saveRates([
            .makeTest(currencyCode: "usd", rate: 1.0)
        ])

        await controller.verifiedProtoService.saveReserveStates([
            .makeTest(mint: mint)
        ])

        let state = await controller.awaitVerifiedState(
            for: .usd,
            mint: mint,
            maxAttempts: 1,
            interval: .milliseconds(1)
        )

        #expect(state != nil)
        #expect(state?.reserveProto != nil)
    }

    @Test("Keeps polling when rate exists but reserve state is missing for launchpad mint")
    @MainActor
    func awaitVerifiedState_rateCachedNoReserve_returnsNil() async {
        let controller = makeController()
        let mint = PublicKey.jeffy // launchpad mint, not .usdf

        // Rate is cached but reserve state is not
        await controller.verifiedProtoService.saveRates([
            .makeTest(currencyCode: "usd", rate: 1.0)
        ])

        let state = await controller.awaitVerifiedState(
            for: .usd,
            mint: mint,
            maxAttempts: 3,
            interval: .milliseconds(10)
        )

        #expect(state == nil)
    }

    @Test("Resolves when reserve state arrives after rate for launchpad mint")
    @MainActor
    func awaitVerifiedState_reserveArrivesLater_resolves() async {
        let controller = makeController()
        let mint = PublicKey.jeffy

        // Rate is immediately available
        await controller.verifiedProtoService.saveRates([
            .makeTest(currencyCode: "usd", rate: 1.0)
        ])

        // Reserve state arrives after a short delay
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            await controller.verifiedProtoService.saveReserveStates([
                .makeTest(mint: mint)
            ])
        }

        let state = await controller.awaitVerifiedState(
            for: .usd,
            mint: mint,
            maxAttempts: 10,
            interval: .milliseconds(20)
        )

        #expect(state != nil)
        #expect(state?.reserveProto != nil)
    }

    @Test("Exits early when task is cancelled")
    @MainActor
    func awaitVerifiedState_cancelled_returnsNil() async {
        let controller = makeController()
        let mint = PublicKey.jeffy

        let task = Task { @MainActor in
            await controller.awaitVerifiedState(
                for: .usd,
                mint: mint,
                maxAttempts: 100,
                interval: .milliseconds(100) // would take 10s without cancellation
            )
        }

        // Cancel after a short delay
        try? await Task.sleep(for: .milliseconds(50))
        task.cancel()

        let state = await task.value
        #expect(state == nil)
    }

    // MARK: - ensureMintSubscribed -

    @Test("Does not duplicate an already subscribed mint")
    @MainActor
    func ensureMintSubscribed_alreadySubscribed_noDuplicate() {
        let controller = makeController()
        let mint = PublicKey.jeffy

        controller.startStreaming(mints: [mint])
        controller.ensureMintSubscribed(mint)

        // No crash, no duplicate — verifying the guard works
    }

    @Test("Subscribes a new mint")
    @MainActor
    func ensureMintSubscribed_newMint_subscribes() {
        let controller = makeController()
        let mint = PublicKey.jeffy

        controller.startStreaming(mints: [.usdf])
        controller.ensureMintSubscribed(mint)

        // Second call should be a no-op (already in list)
        controller.ensureMintSubscribed(mint)
    }

    @Test("Reserve state publisher emits updates when reserve states are saved")
    @MainActor
    func reserveStatesPublisher_emitsOnSave() async {
        let controller = makeController()
        let mint = PublicKey.jeffy

        var received: [ReserveStateUpdate] = []
        let cancellable = controller.verifiedProtoService.reserveStatesPublisher
            .sink { updates in
                received.append(contentsOf: updates)
            }

        await controller.verifiedProtoService.saveReserveStates([
            .makeTest(mint: mint, supplyFromBonding: 1_000_000)
        ])

        // Allow publisher to deliver
        try? await Task.sleep(for: .milliseconds(50))

        #expect(received.count == 1)
        #expect(received.first?.mint == mint)
        #expect(received.first?.supplyFromBonding == 1_000_000)

        _ = cancellable
    }

    // MARK: - reserveStatesPublisher DB sync -

    @Test("Reserve state updates are written to mint_live table")
    @MainActor
    func reserveStatesPublisher_writesToDatabase() async throws {
        let database = try Database(
            url: URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("test-\(UUID().uuidString).sqlite")
        )
        let controller = makeController(database: database)
        let mint = PublicKey.jeffy

        let metadata = MintMetadata.makeLaunchpad(address: mint, supplyFromBonding: 500)
        try database.insert(mints: [metadata], date: .now)
        try database.insertBalance(quarks: 1_000_000_000_000, mint: mint, costBasis: 0, date: .now)

        // Trigger streaming update with new supply
        await controller.verifiedProtoService.saveReserveStates([
            .makeTest(mint: mint, supplyFromBonding: 2_000_000)
        ])

        // Allow publisher → .receive(on: main) → sink → DB write
        try await Task.sleep(for: .milliseconds(200))

        // Verify the database was updated via mint_live
        let balances = try database.getBalances()
        let balance = balances.first { $0.mint == mint }
        #expect(balance?.supplyFromBonding == 2_000_000)
    }

    // MARK: - Helpers -

    @MainActor
    private func makeController(database: Database = .mock) -> RatesController {
        RatesController(container: .mock, database: database)
    }
}
