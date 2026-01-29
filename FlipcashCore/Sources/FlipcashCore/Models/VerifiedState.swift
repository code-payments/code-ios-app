//
//  VerifiedState.swift
//  FlipcashCore
//
//  Created by Claude.
//  Copyright © 2025 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI

/// Bundles verified proofs for intent construction.
/// Contains server-signed exchange rate and optional reserve state for launchpad currencies.
public struct VerifiedState: Sendable {

    /// Exchange rate proof (always required for payments)
    public let rateProto: Ocp_Currency_V1_VerifiedCoreMintFiatExchangeRate

    /// Reserve state proof (only for launchpad currencies, nil for core mint)
    public let reserveProto: Ocp_Currency_V1_VerifiedLaunchpadCurrencyReserveState?

    public init(
        rateProto: Ocp_Currency_V1_VerifiedCoreMintFiatExchangeRate,
        reserveProto: Ocp_Currency_V1_VerifiedLaunchpadCurrencyReserveState? = nil
    ) {
        self.rateProto = rateProto
        self.reserveProto = reserveProto
    }
}

// MARK: - Convenience Accessors

extension VerifiedState {

    public var currencyCode: CurrencyCode? {
        try? CurrencyCode(currencyCode: rateProto.exchangeRate.currencyCode)
    }

    public var exchangeRate: Double {
        rateProto.exchangeRate.exchangeRate
    }

    public var timestamp: Date {
        rateProto.exchangeRate.timestamp.date
    }

    public var supplyFromBonding: UInt64? {
        reserveProto?.reserveState.supplyFromBonding
    }
}
