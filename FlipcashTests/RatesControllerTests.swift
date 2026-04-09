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

        #expect(controller.streamedMints.count == 2) // mint + USDF
        #expect(controller.streamedMints.contains(mint))
        #expect(controller.streamedMints.contains(.usdf))
    }

    @Test("Subscribes a new mint")
    @MainActor
    func ensureMintSubscribed_newMint_subscribes() {
        let controller = makeController()
        let mint = PublicKey.jeffy

        controller.startStreaming(mints: [.usdf])
        controller.ensureMintSubscribed(mint)

        #expect(controller.streamedMints.contains(.usdf))
        #expect(controller.streamedMints.contains(mint))
        #expect(controller.streamedMints.count == 2)
    }

    // MARK: - USDF always subscribed -

    @Test("USDF is always included after startStreaming with empty balances")
    @MainActor
    func startStreaming_emptyBalances_includesUsdf() {
        let controller = makeController()
        controller.startStreaming(mints: [])
        #expect(controller.streamedMints.contains(.usdf))
    }

    @Test("USDF is always included after startStreaming with balances")
    @MainActor
    func startStreaming_withBalances_includesUsdf() {
        let controller = makeController()
        controller.startStreaming(mints: [.jeffy])
        #expect(controller.streamedMints.contains(.usdf))
        #expect(controller.streamedMints.contains(.jeffy))
    }

    @Test("USDF survives a balance refresh that removes all user mints")
    @MainActor
    func updateSubscribedMints_emptyBalances_retainsUsdf() {
        let controller = makeController()
        controller.startStreaming(mints: [.jeffy])
        controller.updateSubscribedMints([])
        #expect(controller.streamedMints.contains(.usdf))
    }

    @Test("Pending mints survive a balance refresh after multiple ensureMintSubscribed calls")
    @MainActor
    func ensureMintSubscribed_balanceRefresh_retainsPending() {
        let controller = makeController()
        let balanceMint = PublicKey.usdf
        let pendingA = PublicKey.jeffy
        let pendingB = PublicKey.usdc

        // Start with one balance mint
        controller.startStreaming(mints: [balanceMint])

        // Subscribe two mints the user doesn't hold
        controller.ensureMintSubscribed(pendingA)
        controller.ensureMintSubscribed(pendingB)

        #expect(controller.streamedMints.count == 3)

        // Simulate a balance refresh (only includes the original balance mint)
        controller.updateSubscribedMints([balanceMint])

        // Both pending mints must survive
        #expect(controller.streamedMints.contains(balanceMint))
        #expect(controller.streamedMints.contains(pendingA))
        #expect(controller.streamedMints.contains(pendingB))
        #expect(controller.streamedMints.count == 3)
    }

    @Test("Pending mint is promoted out of pendingMints when it appears in a balance refresh")
    @MainActor
    func ensureMintSubscribed_promotedByBalance_dropsFromPending() {
        let controller = makeController()
        let balanceMint = PublicKey.usdf
        let newToken = PublicKey.jeffy

        controller.startStreaming(mints: [balanceMint])

        // User views a token they don't own
        controller.ensureMintSubscribed(newToken)
        #expect(controller.streamedMints.count == 2)

        // User buys the token — it now appears in balances
        controller.updateSubscribedMints([balanceMint, newToken])
        #expect(controller.streamedMints.count == 2)

        // User sells all of it — balance refresh no longer includes it,
        // and it should drop because pendingMints was cleared by the
        // previous balance refresh that included it.
        controller.updateSubscribedMints([balanceMint])
        #expect(controller.streamedMints.count == 1)
        #expect(!controller.streamedMints.contains(newToken))
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

    // MARK: - streamedMints filtering -

    @Test("startStreaming sets streamedMints to provided list")
    @MainActor
    func startStreaming_setsStreamedMints() {
        let controller = makeController()
        let mintA = PublicKey.jeffy
        let mintC = PublicKey.usdf

        controller.startStreaming(mints: [mintA, mintC])

        #expect(controller.streamedMints.contains(mintA))
        #expect(controller.streamedMints.contains(mintC))
        #expect(controller.streamedMints.count == 2)
    }

    @Test("updateSubscribedMints expands the mint list")
    @MainActor
    func updateSubscribedMints_addsMint() {
        let controller = makeController()
        let mintA = PublicKey.jeffy
        let mintB = PublicKey.usdc
        let mintC = PublicKey.usdf

        controller.startStreaming(mints: [mintA, mintC])
        controller.updateSubscribedMints([mintA, mintB, mintC])

        #expect(controller.streamedMints.count == 3)
        #expect(controller.streamedMints.contains(mintA))
        #expect(controller.streamedMints.contains(mintB))
        #expect(controller.streamedMints.contains(mintC))
    }

    @Test("updateSubscribedMints shrinks the mint list when mints are removed")
    @MainActor
    func updateSubscribedMints_removesMint() {
        let controller = makeController()
        let mintA = PublicKey.jeffy
        let mintB = PublicKey.usdc

        controller.startStreaming(mints: [mintA, mintB])
        controller.updateSubscribedMints([mintA])

        // mintB is removed, USDF always stays
        #expect(controller.streamedMints.contains(mintA))
        #expect(controller.streamedMints.contains(.usdf))
        #expect(!controller.streamedMints.contains(mintB))
        #expect(controller.streamedMints.count == 2)
    }

    // MARK: - Rate persistence -

    @Test("Rehydrates persisted rates on init")
    @MainActor
    func rehydrate_persistedRates_populatesCache() throws {
        let (database, url) = try makeTempDatabase()
        defer { removeTempDatabase(at: url) }

        let cad = Rate(fx: Decimal(string: "1.4")!, currency: .cad)
        let eur = Rate(fx: Decimal(string: "0.92")!, currency: .eur)
        try database.upsertRates([cad, eur])

        let controller = makeController(database: database)

        #expect(controller.rate(for: .cad) == cad)
        #expect(controller.rate(for: .eur) == eur)
    }

    @Test("Fresh database has no persisted rates on init")
    @MainActor
    func rehydrate_freshDatabase_noRates() throws {
        let (database, url) = try makeTempDatabase()
        defer { removeTempDatabase(at: url) }

        let controller = makeController(database: database)

        #expect(controller.rate(for: .cad) == nil)
        #expect(controller.rate(for: .eur) == nil)
    }

    @Test("updateRates writes incoming batch through to database")
    @MainActor
    func updateRates_writesBatchThrough() async throws {
        let (database, url) = try makeTempDatabase()
        defer { removeTempDatabase(at: url) }

        let controller = makeController(database: database)

        let cad = Rate(fx: Decimal(string: "1.4")!, currency: .cad)
        let eur = Rate(fx: Decimal(string: "0.92")!, currency: .eur)

        controller.updateRates([cad])
        controller.updateRates([eur])

        await controller.awaitPendingRateWrites()

        let persisted = try database.getRates()
        #expect(persisted.count == 2)
        #expect(persisted.contains(cad))
        #expect(persisted.contains(eur))
    }

    @Test("Stream rates overwrite rehydrated stale values in both memory and database")
    @MainActor
    func staleRehydration_doesNotBlockStreamUpdate() async throws {
        let (database, url) = try makeTempDatabase()
        defer { removeTempDatabase(at: url) }

        let stale = Rate(fx: Decimal(string: "1.3")!, currency: .cad)
        try database.upsertRates([stale])

        let controller = makeController(database: database)
        let staleCAD = try #require(controller.rate(for: .cad))
        #expect(staleCAD.fx == Decimal(string: "1.3"))

        let fresh = Rate(fx: Decimal(string: "1.4")!, currency: .cad)
        controller.updateRates([fresh])

        let freshCAD = try #require(controller.rate(for: .cad))
        #expect(freshCAD.fx == Decimal(string: "1.4"))

        await controller.awaitPendingRateWrites()

        let persisted = try database.getRates()
        let persistedCAD = try #require(persisted.first(where: { $0.currency == .cad }))
        #expect(persistedCAD.fx == Decimal(string: "1.4"))
    }

    // MARK: - Helpers -

    /// NOTE: RatesController.init reads `balanceCurrency` / `entryCurrency`
    /// from `UserDefaults.standard` (via `LocalDefaults`). Tests that
    /// mutate those values are NOT parallel-safe with each other or with
    /// any other test on the standard defaults suite. Current tests only
    /// read the defaults, so parallel execution is fine — but adding any
    /// test that does `controller.balanceCurrency = .xxx` would require
    /// `.serialized` on the suite or a proper UserDefaults isolation seam.
    @MainActor
    private func makeController(database: Database = .mock) -> RatesController {
        RatesController(container: .mock, database: database)
    }

    /// Creates an on-disk temp SQLite database. Callers are responsible
    /// for calling ``removeTempDatabase(at:)`` in a `defer` to clean up
    /// the `.sqlite` / `-wal` / `-shm` files.
    private func makeTempDatabase() throws -> (database: Database, url: URL) {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("test-\(UUID().uuidString).sqlite")
        let database = try Database(url: url)
        return (database, url)
    }

    /// Removes the temp database file and its SQLite WAL/SHM sidecars.
    private func removeTempDatabase(at url: URL) {
        let manager = FileManager.default
        let paths: [URL] = [
            url,
            URL(fileURLWithPath: url.path + "-wal"),
            URL(fileURLWithPath: url.path + "-shm"),
        ]
        for path in paths where manager.fileExists(atPath: path.path) {
            try? manager.removeItem(at: path)
        }
    }
}
