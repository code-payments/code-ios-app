//
//  SessionPurchasesTests.swift
//  FlipcashTests
//

import Foundation
import Testing
@testable import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("Session.purchases verified state")
struct SessionPurchasesVerifiedStateTests {

    private static let staleAmount = ExchangedFiat(
        onChainAmount: TokenAmount(quarks: 1_000_000, mint: .usdf),
        nativeAmount: .usd(1),
        currencyRate: .oneToOne
    )

    @Test("buy throws verifiedStateStale when the provided state is past clientMaxAge")
    func buy_throwsStale() async {
        let session = Session.unverifiedMock
        let stale = VerifiedState.stale(bonded: false)

        do {
            _ = try await session.purchases.buy(
                amount: Self.staleAmount,
                verifiedState: stale,
                of: .usdf
            )
            Issue.record("Expected verifiedStateStale to be thrown")
        } catch Session.Error.verifiedStateStale {
            // expected
        } catch {
            Issue.record("Unexpected error thrown: \(error)")
        }
    }

    @Test("buyNewCurrency throws verifiedStateStale when the provided state is past clientMaxAge")
    func buyNewCurrency_throwsStale() async {
        let session = Session.unverifiedMock
        let stale = VerifiedState.stale(bonded: false)

        do {
            _ = try await session.purchases.buyNewCurrency(
                amount: Self.staleAmount,
                feeAmount: Self.staleAmount,
                verifiedState: stale,
                mint: .usdf
            )
            Issue.record("Expected verifiedStateStale to be thrown")
        } catch Session.Error.verifiedStateStale {
            // expected
        } catch {
            Issue.record("Unexpected error thrown: \(error)")
        }
    }

    @Test("sell throws verifiedStateStale when the provided state is past clientMaxAge")
    func sell_throwsStale() async {
        let session = Session.unverifiedMock
        let stale = VerifiedState.stale(bonded: false)

        do {
            _ = try await session.purchases.sell(
                amount: Self.staleAmount,
                verifiedState: stale,
                in: .usdf
            )
            Issue.record("Expected verifiedStateStale to be thrown")
        } catch Session.Error.verifiedStateStale {
            // expected
        } catch {
            Issue.record("Unexpected error thrown: \(error)")
        }
    }
}
