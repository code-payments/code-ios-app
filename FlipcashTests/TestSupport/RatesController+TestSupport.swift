//
//  RatesController+TestSupport.swift
//  FlipcashTests
//
//  Created by GitHub Copilot on 2026-02-01.
//

import Foundation
import FlipcashCore
import FlipcashStore
@testable import Flipcash

extension RatesController {
    /// Creates a controller that publishes its display currency to a test-only suite, so no test
    /// writes the App Group defaults the notification extensions read.
    @MainActor
    convenience init(container: Container, database: Database) {
        self.init(container: container, database: database, sharedDefaults: UserDefaults(suiteName: "FlipcashTests.sharedDefaults"))
    }

    /// Configure balance currency and inject rates for tests.
    @MainActor
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
    @MainActor
    func awaitPendingRateWrites() async {
        await withCheckedContinuation { continuation in
            rateWriteQueue.async {
                continuation.resume()
            }
        }
    }
}