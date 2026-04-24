//
//  VerifiedState+TestSupport.swift
//  FlipcashTests
//

import Foundation
import SwiftProtobuf
@testable import Flipcash
import FlipcashCore
import FlipcashAPI

extension VerifiedState {
    static func makeForTest(
        rateTimestamp: Date,
        reserveTimestamp: Date?,
        currencyCode: String = "USD",
        exchangeRate: Double = 1.0,
        supplyFromBonding: UInt64 = 0
    ) -> VerifiedState {
        var rate = Ocp_Currency_V1_VerifiedCoreMintFiatExchangeRate()
        rate.exchangeRate.timestamp = Google_Protobuf_Timestamp(date: rateTimestamp)
        rate.exchangeRate.currencyCode = currencyCode
        rate.exchangeRate.exchangeRate = exchangeRate

        let reserve: Ocp_Currency_V1_VerifiedLaunchpadCurrencyReserveState? = reserveTimestamp.map {
            var r = Ocp_Currency_V1_VerifiedLaunchpadCurrencyReserveState()
            r.reserveState.timestamp = Google_Protobuf_Timestamp(date: $0)
            r.reserveState.supplyFromBonding = supplyFromBonding
            return r
        }

        return VerifiedState(rateProto: rate, reserveProto: reserve)
    }

    /// A non-stale test fixture. Reserve is included by default since most
    /// flows that pin state are bonded — pass `bonded: false` for non-bonded
    /// (USDF) flows.
    static func fresh(
        bonded: Bool = true,
        currencyCode: String = "USD",
        exchangeRate: Double = 1.0,
        supplyFromBonding: UInt64 = 1_000_000_000
    ) -> VerifiedState {
        makeForTest(
            rateTimestamp: Date(),
            reserveTimestamp: bonded ? Date() : nil,
            currencyCode: currencyCode,
            exchangeRate: exchangeRate,
            supplyFromBonding: bonded ? supplyFromBonding : 0
        )
    }

    /// A stale test fixture (1 second past `clientMaxAge`).
    static func stale(bonded: Bool = true) -> VerifiedState {
        let pastCutoff = Date().addingTimeInterval(-VerifiedState.clientMaxAge - 1)
        return makeForTest(
            rateTimestamp: pastCutoff,
            reserveTimestamp: bonded ? pastCutoff : nil
        )
    }
}
