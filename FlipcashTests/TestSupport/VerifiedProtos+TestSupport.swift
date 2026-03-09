//
//  VerifiedProtos+TestSupport.swift
//  FlipcashTests
//
//  Created by Claude.
//

import FlipcashCore
import FlipcashAPI

extension Ocp_Currency_V1_VerifiedCoreMintFiatExchangeRate {
    static func makeTest(currencyCode: String, rate: Double) -> Self {
        var proto = Self()
        proto.exchangeRate.currencyCode = currencyCode
        proto.exchangeRate.exchangeRate = rate
        return proto
    }
}

extension Ocp_Currency_V1_VerifiedLaunchpadCurrencyReserveState {
    static func makeTest(mint: PublicKey) -> Self {
        var proto = Self()
        proto.reserveState.mint = mint.solanaAccountID
        return proto
    }
}
