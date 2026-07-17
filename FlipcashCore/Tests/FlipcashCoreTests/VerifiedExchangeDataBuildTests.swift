//
//  VerifiedExchangeDataBuildTests.swift
//  FlipcashCoreTests
//

import Foundation
import Testing
import FlipcashAPI
@testable import FlipcashCore

@Suite("VerifiedExchangeData builder")
struct VerifiedExchangeDataBuildTests {

    @Test("Encodes mint, quarks, native, rate, and reserve proof")
    func encodesAllFields() {
        let pin = VerifiedState(
            rateProto: .makeTest(currencyCode: "USD", rate: 1.0),
            reserveProto: .makeTest(mint: .jeffy, supplyFromBonding: 50_000 * 10_000_000_000)
        )
        let amount = ExchangedFiat.compute(
            onChainAmount: TokenAmount(quarks: 2_000 * 10_000_000_000, mint: .jeffy),
            rate: pin.rate,
            supplyQuarks: pin.supplyFromBonding
        )

        let proto = Ocp_Transaction_V1_VerifiedExchangeData(amount: amount, verifiedState: pin)

        #expect(proto.quarks == amount.onChainAmount.quarks)
        #expect(proto.nativeAmount == amount.nativeAmount.doubleValue)
        #expect(proto.mint == amount.mint.solanaAccountID)
        #expect(proto.hasLaunchpadCurrencyReserveState)
    }

    @Test("Omits reserve proof for the core-mint path")
    func omitsReserveForCoreMint() {
        let pin = VerifiedState(rateProto: .makeTest(currencyCode: "USD", rate: 1.0))
        let amount = ExchangedFiat(nativeAmount: .usd(20), rate: pin.rate)

        let proto = Ocp_Transaction_V1_VerifiedExchangeData(amount: amount, verifiedState: pin)

        #expect(!proto.hasLaunchpadCurrencyReserveState)
    }
}

private extension Ocp_Currency_V1_VerifiedCoreMintFiatExchangeRate {
    static func makeTest(currencyCode: String, rate: Double) -> Self {
        var proto = Self()
        proto.exchangeRate.currencyCode = currencyCode
        proto.exchangeRate.exchangeRate = rate
        return proto
    }
}

private extension Ocp_Currency_V1_VerifiedLaunchpadCurrencyReserveState {
    static func makeTest(mint: PublicKey, supplyFromBonding: UInt64 = 0) -> Self {
        var proto = Self()
        proto.reserveState.mint = mint.solanaAccountID
        proto.reserveState.supplyFromBonding = supplyFromBonding
        return proto
    }
}
