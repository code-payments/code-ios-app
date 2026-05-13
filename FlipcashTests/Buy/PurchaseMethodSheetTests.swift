//
//  PurchaseMethodSheetTests.swift
//  FlipcashTests
//
//  Created by Raul Riera on 2026-05-12.
//

import Foundation
import Testing
@testable import FlipcashCore
@testable import Flipcash

/// Runs serialized — both test cases mutate the `BetaFlags.shared`
/// singleton (UserDefaults-backed), so parallel execution with any other
/// suite that reads `enableCoinbase` would race on the global flag.
@Suite("PurchaseMethodSheet — visibility", .serialized)
@MainActor
struct PurchaseMethodSheetTests {

    /// Runs `body` with `BetaFlags.enableCoinbase` forced to the requested
    /// state, restoring the original value (which is persisted to UserDefaults
    /// by `BetaFlags.set`) when `body` returns. Without restoration the suite
    /// leaks the disabled flag to whichever suite runs next.
    private static func withCoinbaseBetaFlag<R>(enabled: Bool, _ body: () throws -> R) rethrows -> R {
        let original = BetaFlags.shared.hasEnabled(.enableCoinbase)
        BetaFlags.shared.set(.enableCoinbase, enabled: enabled)
        defer { BetaFlags.shared.set(.enableCoinbase, enabled: original) }
        return try body()
    }

    /// Builds a `SessionContainer` whose `userFlags.hasCoinbase` is `true`.
    /// Tests that need Apple Pay visible reuse this fixture.
    private static func makeContainerWithCoinbase() throws -> SessionContainer {
        let container = try SessionContainer.makeTest(holdings: [])
        container.session.userFlags = UserFlags(
            isRegistered: true,
            isStaff: false,
            onrampProviders: [.coinbaseVirtual],
            preferredOnrampProvider: .coinbaseVirtual,
            minBuildNumber: 0,
            billExchangeDataTimeout: nil,
            newCurrencyPurchaseAmount: .zero(mint: .usdf),
            newCurrencyFeeAmount: .zero(mint: .usdf),
            withdrawalFeeAmount: TokenAmount(quarks: 0, mint: .usdf)
        )
        return container
    }

    @Test("Apple Pay row hidden when hasCoinbaseOnramp is false")
    func applePayHiddenWhenNoCoinbase() throws {
        try Self.withCoinbaseBetaFlag(enabled: false) {
            let container = try SessionContainer.makeTest(holdings: [])
            // Default test session has no userFlags set, so hasCoinbase is false.

            let methods = PurchaseMethodSheet.methods(forSession: container.session)

            #expect(!methods.contains(.applePay))
            #expect(methods.contains(.phantom))
            #expect(methods.contains(.otherWallet))
        }
    }

    @Test("Apple Pay row visible and ordered first when hasCoinbaseOnramp is true")
    func applePayVisibleAndFirst() throws {
        try Self.withCoinbaseBetaFlag(enabled: false) {
            let container = try Self.makeContainerWithCoinbase()

            let methods = PurchaseMethodSheet.methods(forSession: container.session)

            #expect(methods.first == .applePay)
            #expect(methods.contains(.phantom))
            #expect(methods.contains(.otherWallet))
        }
    }
}
