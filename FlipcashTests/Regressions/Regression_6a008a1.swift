//
//  Regression_6a008a1.swift
//  Flipcash
//
//  App Hang: AccountSelectionScreen blocks main thread because
//            HistoricalAccount.init eagerly builds an AccountCluster
//            whose authority is `.derive(using:mnemonic:)` — i.e.
//            BIP-39 PBKDF2-HMAC-SHA512 / 2048 rounds per instance.
//            Constructing N historical accounts at screen-open time
//            multiplies the cost and stalls the main run loop.
//
//  Fix:      Defer key derivation out of HistoricalAccount.init so
//            construction is microseconds and the heavy work runs
//            only when the user selects an account.
//

import Foundation
import Testing
@testable import Flipcash
@testable import FlipcashCore

@Suite("Regression: 6a008a1 – AccountSelectionScreen hang from BIP-39 PBKDF2 in HistoricalAccount.init", .bug("6a008a1e8c3285d1a52ac2c2"))
struct Regression_6a008a1 {

    @Test("HistoricalAccount construction is fast (no eager BIP-39 PBKDF2 derivation)")
    @MainActor
    func historicalAccount_init_doesNotDeriveKeys() {
        let descriptions = Array(AccountDescription.mockMany().prefix(10))
        var results: [HistoricalAccount] = []

        let clock = ContinuousClock()
        let elapsed = clock.measure {
            results = descriptions.map { HistoricalAccount(details: $0) }
        }
        // One derivation timed in the same run, so a slower host (Thread Sanitizer, a loaded
        // CI runner) slows both sides. The regression costs one derivation per init.
        let oneDerivation = clock.measure {
            _ = DerivedKey.derive(using: .primary(), mnemonic: descriptions[0].account.mnemonic)
        }

        // Observe the result so the optimizer can't elide construction.
        #expect(results.count == 10)
        #expect(elapsed < oneDerivation, "elapsed=\(elapsed) oneDerivation=\(oneDerivation)")
    }
}
