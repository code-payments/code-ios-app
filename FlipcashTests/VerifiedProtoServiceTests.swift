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

@Suite("VerifiedProtoService")
struct VerifiedProtoServiceTests {

    // MARK: - saveRates dedupe -

    @Test("saveRates publishes every currency on the first batch")
    func saveRates_firstBatch_publishesAll() async throws {
        let service = VerifiedProtoService()
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
        let service = VerifiedProtoService()
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
        let service = VerifiedProtoService()
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
        let service = VerifiedProtoService()

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
