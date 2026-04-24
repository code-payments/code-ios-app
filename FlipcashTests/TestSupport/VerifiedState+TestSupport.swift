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
        reserveTimestamp: Date?
    ) -> VerifiedState {
        var rate = Ocp_Currency_V1_VerifiedCoreMintFiatExchangeRate()
        rate.exchangeRate.timestamp = Google_Protobuf_Timestamp(date: rateTimestamp)

        let reserve: Ocp_Currency_V1_VerifiedLaunchpadCurrencyReserveState? = reserveTimestamp.map {
            var r = Ocp_Currency_V1_VerifiedLaunchpadCurrencyReserveState()
            r.reserveState.timestamp = Google_Protobuf_Timestamp(date: $0)
            return r
        }

        return VerifiedState(rateProto: rate, reserveProto: reserve)
    }

    /// A non-stale test fixture. Reserve is included by default since most
    /// flows that pin state are bonded — pass `bonded: false` for non-bonded
    /// (USDF) flows.
    static func fresh(bonded: Bool = true) -> VerifiedState {
        makeForTest(
            rateTimestamp: Date(),
            reserveTimestamp: bonded ? Date() : nil
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
