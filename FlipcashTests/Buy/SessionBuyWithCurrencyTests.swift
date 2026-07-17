//
//  SessionBuyWithCurrencyTests.swift
//  FlipcashTests
//

import Foundation
import Testing
@testable import FlipcashCore
@testable import Flipcash

@Suite("Session.buy(with:) — pre-RPC guards")
@MainActor
struct SessionBuyWithCurrencyTests {

    private static func makeAmount() -> ExchangedFiat {
        ExchangedFiat(nativeAmount: FiatAmount.usd(1), rate: .oneToOne)
    }

    @Test("A stale pin throws verifiedStateStale before any network call")
    func stalePin_throws() async throws {
        let container = try SessionContainer.makeTest(holdings: [])

        await #expect(throws: Session.Error.verifiedStateStale) {
            try await container.session.buy(
                amount: Self.makeAmount(),
                with: .jeffy,
                verifiedState: .stale(),
                of: PublicKey.usdcAuthority
            )
        }
    }

    @Test("A pin without reserve supply throws missingSupply")
    func missingSupply_throws() async throws {
        let container = try SessionContainer.makeTest(holdings: [])

        await #expect(throws: Session.Error.missingSupply) {
            try await container.session.buy(
                amount: Self.makeAmount(),
                with: .jeffy,
                verifiedState: .fresh(bonded: false),
                of: PublicKey.usdcAuthority
            )
        }
    }
}
