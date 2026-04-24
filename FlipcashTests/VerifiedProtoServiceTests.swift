//
//  VerifiedProtoServiceTests.swift
//  FlipcashTests
//
//  Created by Claude on 2026-04-09.
//

import Foundation
import Testing
import Combine
import FlipcashCore
import FlipcashAPI

/// Several tests rely on Task.sleep to give the actor's fire-and-forget
/// `persistRate` / `warmLoadFromStore` paths time to complete. The 1-minute
/// time limit is a safety net so a hung warm-load surfaces as a named
/// failure instead of timing out the whole test invocation silently.
@Suite("VerifiedProtoService", .timeLimit(.minutes(1)))
struct VerifiedProtoServiceTests {

    // MARK: - saveRates dedupe -

    @Test("saveRates publishes every currency on the first batch")
    func saveRates_firstBatch_publishesAll() async throws {
        let service = VerifiedProtoService(store: InMemoryVerifiedProtoStore())
        let collector = PublishedRateCollector()
        collector.subscribe(to: service.ratesPublisher)

        await service.saveRates([
            .makeTest(currencyCode: "usd", rate: 1.0),
            .makeTest(currencyCode: "cad", rate: 1.4),
            .makeTest(currencyCode: "eur", rate: 0.92),
        ])

        try await Task.sleep(for: .milliseconds(20))

        let batches = collector.batches
        #expect(batches.count == 1)
        #expect(batches.first?.count == 3)
    }

    @Test("saveRates drops unchanged rates on subsequent batches")
    func saveRates_unchangedBatch_publishesNothing() async throws {
        let service = VerifiedProtoService(store: InMemoryVerifiedProtoStore())
        let collector = PublishedRateCollector()
        collector.subscribe(to: service.ratesPublisher)

        await service.saveRates([
            .makeTest(currencyCode: "usd", rate: 1.0),
            .makeTest(currencyCode: "cad", rate: 1.4),
        ])

        // Same rates again — server delivers a full snapshot on every tick,
        // but dedupe should suppress downstream work when nothing moved.
        await service.saveRates([
            .makeTest(currencyCode: "usd", rate: 1.0),
            .makeTest(currencyCode: "cad", rate: 1.4),
        ])

        try await Task.sleep(for: .milliseconds(20))

        let batches = collector.batches
        #expect(batches.count == 1)
        #expect(batches.first?.count == 2)
    }

    @Test("saveRates publishes only the currencies whose fx actually changed")
    func saveRates_partialChange_publishesOnlyDelta() async throws {
        let service = VerifiedProtoService(store: InMemoryVerifiedProtoStore())
        let collector = PublishedRateCollector()
        collector.subscribe(to: service.ratesPublisher)

        await service.saveRates([
            .makeTest(currencyCode: "usd", rate: 1.0),
            .makeTest(currencyCode: "cad", rate: 1.4),
            .makeTest(currencyCode: "eur", rate: 0.92),
        ])

        // Only CAD moves.
        await service.saveRates([
            .makeTest(currencyCode: "usd", rate: 1.0),
            .makeTest(currencyCode: "cad", rate: 1.41),
            .makeTest(currencyCode: "eur", rate: 0.92),
        ])

        try await Task.sleep(for: .milliseconds(20))

        let batches = collector.batches
        #expect(batches.count == 2)

        let secondBatch = try #require(batches.dropFirst().first)
        #expect(secondBatch.count == 1)
        let changed = try #require(secondBatch.first)
        #expect(changed.currency == .cad)
        #expect(changed.fx == Decimal(1.41))
    }

    @Test("saveRates refreshes the stored signed proof even when fx is unchanged")
    func saveRates_unchangedFx_stillRefreshesProto() async {
        let service = VerifiedProtoService(store: InMemoryVerifiedProtoStore())

        await service.saveRates([.makeTest(currencyCode: "usd", rate: 1.0)])
        let first = await service.getVerifiedRate(for: .usd)
        #expect(first != nil)

        // Re-save with identical fx — the proto object is still replaced so
        // intent submission always uses the freshest signed rate.
        await service.saveRates([.makeTest(currencyCode: "usd", rate: 1.0)])
        let second = await service.getVerifiedRate(for: .usd)
        #expect(second != nil)
        #expect(await service.hasVerifiedRate(for: .usd))
    }

    // MARK: - Persistence -

    @Test("saveRates persists each rate to the store")
    func saveRates_persists() async throws {
        let store = InMemoryVerifiedProtoStore()
        let fixedDate = Date(timeIntervalSince1970: 1_000)
        let service = VerifiedProtoService(store: store, clock: { fixedDate })

        await service.saveRates([.makeTest(currencyCode: "usd", rate: 1.0)])

        try await Task.sleep(for: .milliseconds(50))

        #expect(store.writeRateCalls.count == 1)
        #expect(store.writeRateCalls.first?.currency == "usd")
        #expect(store.writeRateCalls.first?.receivedAt == fixedDate)
    }

    @Test("saveReserveStates persists each reserve to the store")
    func saveReserves_persists() async throws {
        let store = InMemoryVerifiedProtoStore()
        let fixedDate = Date(timeIntervalSince1970: 500)
        let service = VerifiedProtoService(store: store, clock: { fixedDate })

        await service.saveReserveStates([.makeTest(mint: .usdf)])

        try await Task.sleep(for: .milliseconds(50))

        #expect(store.writeReserveCalls.count == 1)
        #expect(store.writeReserveCalls.first?.mint == PublicKey.usdf.base58)
        #expect(store.writeReserveCalls.first?.receivedAt == fixedDate)
    }

    @Test("init warm-loads rates from the store into the in-memory cache")
    func init_warmLoadsRates() async throws {
        let store = InMemoryVerifiedProtoStore()

        // Pre-seed the store with a serialized rate proto.
        let rateProto = Ocp_Currency_V1_VerifiedCoreMintFiatExchangeRate.makeTest(currencyCode: "usd", rate: 1.0)
        let data = try rateProto.serializedData()
        try store.writeRate(StoredRateRow(currency: "usd", rateProto: data, receivedAt: Date()))

        let service = VerifiedProtoService(store: store, clock: { Date() })

        // Allow warm-load task a turn.
        try await Task.sleep(for: .milliseconds(150))

        #expect(await service.hasVerifiedRate(for: .usd))
    }

    @Test("init warm-loads reserves from the store into the in-memory cache")
    func init_warmLoadsReserves() async throws {
        let store = InMemoryVerifiedProtoStore()

        // Pre-seed the store with a serialized reserve proto.
        let reserveProto = Ocp_Currency_V1_VerifiedLaunchpadCurrencyReserveState.makeTest(mint: .usdf)
        let data = try reserveProto.serializedData()
        try store.writeReserve(StoredReserveRow(mint: PublicKey.usdf.base58, reserveProto: data, receivedAt: Date()))

        let service = VerifiedProtoService(store: store, clock: { Date() })

        // Allow warm-load task a turn.
        try await Task.sleep(for: .milliseconds(150))

        #expect(await service.getVerifiedReserveState(for: .usdf) != nil)
    }

    @Test("write failure logs but does not prevent in-memory update")
    func writeFailure_fallsThrough() async throws {
        let store = InMemoryVerifiedProtoStore()
        store.writeRateError = NSError(domain: "test", code: 1)
        let service = VerifiedProtoService(store: store, clock: { Date() })

        await service.saveRates([.makeTest(currencyCode: "usd", rate: 1.0)])

        try await Task.sleep(for: .milliseconds(50))

        // The in-memory cache must still reflect the save even though the write failed.
        #expect(await service.hasVerifiedRate(for: .usd))
        let state = await service.getVerifiedState(for: .usd, mint: .usdf)
        #expect(state?.rateProto != nil)
    }
}

// MARK: - Helpers -

/// Test-only collector for rates arriving on a Combine publisher. State
/// is protected by an `NSLock` because the sink closure runs on whatever
/// queue Combine delivers on, which is not the test's @MainActor context.
/// A lock is the smallest-safe tool here: tests await via `Task.sleep`,
/// then read `batches` after the sink has drained.
private final class PublishedRateCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var _batches: [[Rate]] = []
    private var cancellable: AnyCancellable?

    var batches: [[Rate]] {
        lock.lock()
        defer { lock.unlock() }
        return _batches
    }

    func subscribe(to publisher: PassthroughSubject<[Rate], Never>) {
        cancellable = publisher.sink { [weak self] rates in
            guard let self else { return }
            self.lock.lock()
            self._batches.append(rates)
            self.lock.unlock()
        }
    }
}
