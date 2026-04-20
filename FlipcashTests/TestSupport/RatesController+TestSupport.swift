//
//  RatesController+TestSupport.swift
//  FlipcashTests
//
//  Created by GitHub Copilot on 2026-02-01.
//

import Foundation
import FlipcashCore
@testable import Flipcash

extension RatesController {
    /// Configure entry currency and inject rates for tests.
    func configureTestRates(entryCurrency: CurrencyCode? = nil, rates: [Rate]) {
        if let entryCurrency {
            self.entryCurrency = entryCurrency
        }

        updateRates(rates)
    }

    /// Block until all pending rate writes on the background queue have
    /// finished. `updateRates` dispatches the SQLite upsert asynchronously
    /// to avoid blocking the main thread on I/O, so tests that read from
    /// the database immediately after calling `updateRates` need to drain
    /// the queue first.
    func awaitPendingRateWrites() async {
        await withCheckedContinuation { continuation in
            rateWriteQueue.async {
                continuation.resume()
            }
        }
    }

    /// Drive a reserve-state update through the same publisher path that
    /// live streaming uses, then poll until the Combine main-queue hop has
    /// populated `cachedReserveSupply`. Poll-until beats a fixed sleep under
    /// parallel-test load where the main queue can be saturated. Mirrors
    /// `updateRates(_:)`'s role for rates.
    @MainActor
    func deliverTestReserveState(mint: PublicKey, supplyFromBonding: UInt64) async {
        await verifiedProtoService.saveReserveStates([
            .makeTest(mint: mint, supplyFromBonding: supplyFromBonding)
        ])
        for _ in 0..<100 { // up to ~1s
            if cachedReserveSupply[mint] == supplyFromBonding {
                return
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}