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

@Suite("PurchaseMethodSheet — visibility")
@MainActor
struct PurchaseMethodSheetTests {

    /// Disables the global Coinbase beta-flag toggle so tests deterministically
    /// drive `hasCoinbaseOnramp` through `userFlags?.hasCoinbase` only. Without
    /// this, a developer who happened to enable the beta flag on their machine
    /// would see different behavior than CI.
    private static func clearBetaFlag() {
        BetaFlags.shared.set(.enableCoinbase, enabled: false)
    }

    @Test("Apple Pay row hidden when hasCoinbaseOnramp is false")
    func applePayHiddenWhenNoCoinbase() throws {
        Self.clearBetaFlag()
        let container = try SessionContainer.makeTest(holdings: [])
        // Default test session has no userFlags set, so hasCoinbase is false.

        let methods = PurchaseMethodSheet.methods(forSession: container.session)

        #expect(!methods.contains(.applePay))
        #expect(methods.contains(.phantom))
        #expect(methods.contains(.otherWallet))
    }

    @Test("Apple Pay row visible when hasCoinbaseOnramp is true")
    func applePayVisibleWhenCoinbaseAvailable() throws {
        Self.clearBetaFlag()
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

        let methods = PurchaseMethodSheet.methods(forSession: container.session)

        #expect(methods.contains(.applePay))
        #expect(methods.contains(.phantom))
        #expect(methods.contains(.otherWallet))
    }

    @Test("Apple Pay appears first when available")
    func applePayOrderedFirst() throws {
        Self.clearBetaFlag()
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

        let methods = PurchaseMethodSheet.methods(forSession: container.session)

        #expect(methods.first == .applePay)
    }
}
