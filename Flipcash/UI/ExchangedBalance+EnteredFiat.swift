//
//  ExchangedBalance+EnteredFiat.swift
//  Flipcash
//

import Foundation
import FlipcashCore

extension ExchangedBalance {

    /// Prices a user-entered fiat `amount` against this balance for amount-entry
    /// screens. USDF maps straight through; a bonded mint resolves via the bonding
    /// curve. When the entered value exceeds the curve's TVL (the compute clamps
    /// to the full supply), returns a synthetic over-balance value whose
    /// `onChainAmount` is a sentinel (`quarks + 1`) so the entered amount stays
    /// on screen and `Session.hasSufficientFunds` reports `.insufficient` with a
    /// real shortfall — this value is never transported.
    /// Returns nil for a non-positive amount or a bonded mint with no supply.
    func enteredFiat(for amount: Decimal, rate: Rate) -> ExchangedFiat? {
        guard amount > 0 else { return nil }

        let mint = stored.mint
        let entered = FiatAmount(value: amount, currency: rate.currency)

        if mint == .usdf {
            return ExchangedFiat(nativeAmount: entered, rate: rate)
        }

        guard let supplyQuarks = stored.supplyFromBonding else { return nil }

        if let priced = ExchangedFiat.compute(
            fromEntered: entered,
            rate: rate,
            mint: mint,
            supplyQuarks: supplyQuarks
        ), priced.onChainAmount.quarks < supplyQuarks {
            return priced
        }

        return ExchangedFiat(
            onChainAmount: TokenAmount(quarks: stored.quarks + 1, mint: mint),
            nativeAmount: entered,
            currencyRate: rate
        )
    }
}
