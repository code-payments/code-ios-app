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
}
