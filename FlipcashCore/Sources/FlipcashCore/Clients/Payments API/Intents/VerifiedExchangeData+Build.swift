//
//  VerifiedExchangeData+Build.swift
//  FlipcashCore
//

import Foundation
import FlipcashAPI

extension Ocp_Transaction_V1_VerifiedExchangeData {
    /// The client's signed valuation of `amount`, carrying the rate proof and,
    /// for launchpad mints, the reserve-state proof the server re-values against.
    init(amount: ExchangedFiat, verifiedState: VerifiedState) {
        self = .with {
            $0.mint = amount.mint.solanaAccountID
            $0.quarks = amount.onChainAmount.quarks
            $0.nativeAmount = amount.nativeAmount.doubleValue
            $0.coreMintFiatExchangeRate = verifiedState.rateProto
            if let reserveProto = verifiedState.reserveProto {
                $0.launchpadCurrencyReserveState = reserveProto
            }
        }
    }
}
