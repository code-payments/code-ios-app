//
//  VerifiedProtos+TestSupport.swift
//  FlipcashTests
//
//  Created by Claude.
//

import Foundation
import FlipcashCore
import FlipcashAPI
import SwiftProtobuf

extension Ocp_Currency_V1_VerifiedCoreMintFiatExchangeRate {
    static func makeTest(currencyCode: String, rate: Double) -> Self {
        var proto = Self()
        proto.exchangeRate.currencyCode = currencyCode
        proto.exchangeRate.exchangeRate = rate
        return proto
    }

    /// A rate whose server-signed timestamp is well inside the 13-minute freshness window.
    static func freshRate(currencyCode: String = "USD", rate: Double = 1.0) -> Self {
        var proto = Self()
        proto.exchangeRate.currencyCode = currencyCode
        proto.exchangeRate.exchangeRate = rate
        proto.exchangeRate.timestamp = Google_Protobuf_Timestamp(date: Date())
        return proto
    }

    /// A rate whose server-signed timestamp is older than `clientMaxAge` (13 minutes).
    static func staleRate(currencyCode: String = "USD", rate: Double = 1.0) -> Self {
        var proto = Self()
        proto.exchangeRate.currencyCode = currencyCode
        proto.exchangeRate.exchangeRate = rate
        proto.exchangeRate.timestamp = Google_Protobuf_Timestamp(date: Date().addingTimeInterval(-(VerifiedState.clientMaxAge + 60)))
        return proto
    }
}

extension Ocp_Currency_V1_VerifiedLaunchpadCurrencyReserveState {
    static func makeTest(mint: PublicKey, supplyFromBonding: UInt64 = 0) -> Self {
        var proto = Self()
        proto.reserveState.mint = mint.solanaAccountID
        proto.reserveState.supplyFromBonding = supplyFromBonding
        return proto
    }

    /// A reserve state whose server-signed timestamp is well inside the freshness window.
    static func freshReserve(mint: PublicKey = .jeffy, supplyFromBonding: UInt64 = 0) -> Self {
        var proto = Self()
        proto.reserveState.mint = mint.solanaAccountID
        proto.reserveState.supplyFromBonding = supplyFromBonding
        proto.reserveState.timestamp = Google_Protobuf_Timestamp(date: Date())
        return proto
    }
}
