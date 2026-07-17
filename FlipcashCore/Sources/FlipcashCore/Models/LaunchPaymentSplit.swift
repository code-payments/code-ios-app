//
//  LaunchPaymentSplit.swift
//  FlipcashCore
//

import Foundation

/// Splits a fixed-USD launch cost into the swap and fee legs a launchpad-funded
/// currency creation pays, denominated in the payment token's quarks.
public enum LaunchPaymentSplit {

    /// Returns the swap and fee legs, or `nil` when the balance can't seat the
    /// split. Natives are the exact USD components (the wire's full-amount
    /// valuation must equal the fixed USD total); quarks are curve-derived and
    /// the total is capped to `balanceUSD` so rounding can't overshoot reserves.
    ///
    /// `rate` and `balanceUSD` are USD; the caller unwraps the pin's reserve
    /// supply before calling.
    public static func compute(
        purchaseUSD: Decimal,
        feeUSD: Decimal,
        rate: Rate,
        paymentMint: PublicKey,
        supplyQuarks: UInt64,
        balanceUSD: FiatAmount
    ) -> (swap: ExchangedFiat, fee: ExchangedFiat)? {
        guard
            let feeLeg = ExchangedFiat.compute(
                fromEntered: .usd(feeUSD), rate: rate, mint: paymentMint, supplyQuarks: supplyQuarks
            ),
            let totalLeg = ExchangedFiat.compute(
                fromEntered: .usd(purchaseUSD + feeUSD), rate: rate, mint: paymentMint,
                supplyQuarks: supplyQuarks, balance: balanceUSD
            )
        else { return nil }

        let feeQuarks = feeLeg.onChainAmount.quarks
        let totalQuarks = totalLeg.onChainAmount.quarks
        guard totalQuarks >= feeQuarks else { return nil }
        let swapQuarks = totalQuarks - feeQuarks

        let fee = ExchangedFiat(
            onChainAmount: TokenAmount(quarks: feeQuarks, mint: paymentMint),
            nativeAmount: .usd(feeUSD),
            currencyRate: rate
        )
        let swap = ExchangedFiat(
            onChainAmount: TokenAmount(quarks: swapQuarks, mint: paymentMint),
            nativeAmount: .usd(purchaseUSD),
            currencyRate: rate
        )
        return (swap, fee)
    }
}
