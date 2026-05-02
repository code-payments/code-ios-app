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
    /// Configure balance currency and inject rates for tests.
    func configureTestRates(balanceCurrency: CurrencyCode? = nil, rates: [Rate]) {
        if let balanceCurrency {
            self.balanceCurrency = balanceCurrency
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
}