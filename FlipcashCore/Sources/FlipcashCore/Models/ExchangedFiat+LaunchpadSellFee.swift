//
//  ExchangedFiat+LaunchpadSellFee.swift
//  FlipcashCore
//

import Foundation

public extension ExchangedFiat {
    /// The launchpad pool's sell fee taken from this amount when it is sold.
    ///
    /// Native is scaled by the *actual* on-chain ratio (not the static bps),
    /// so a fee that rounds down to 0 quarks also displays as 0 fiat.
    func launchpadSellFee(bps: UInt64) -> ExchangedFiat {
        // Split multiply: quarks × bps overflows UInt64 for large launchpad
        // balances (10-decimal quarks). Exact for any bps ≤ 10⁴.
        let bps = min(bps, 10_000)
        let quarks = onChainAmount.quarks
        let feeQuarks = (quarks / 10_000) * bps + (quarks % 10_000) * bps / 10_000
        let feeOnChain = TokenAmount(
            quarks: feeQuarks,
            mint: onChainAmount.mint
        )
        let scale: Decimal = onChainAmount.quarks > 0
            ? Decimal(feeQuarks) / Decimal(onChainAmount.quarks)
            : 0
        return ExchangedFiat(
            onChainAmount: feeOnChain,
            nativeAmount: nativeAmount * scale,
            currencyRate: currencyRate,
        )
    }
}

public extension FiatAmount {
    /// The gross fiat whose launchpad sell proceeds net to this amount after
    /// the pool fee: `net / (1 − bps/10⁴)`.
    ///
    /// Unrounded by design — callers feed the result to
    /// `ExchangedFiat.compute(fromEntered:)`, whose fiat→quark boundary owns
    /// the rounding.
    func grossingUpLaunchpadSellFee(bps: UInt64) -> FiatAmount {
        // A 100% fee can't be grossed up — the guard keeps server-sourced bps
        // from dividing by zero; the flow gates insufficient downstream anyway.
        guard bps < 10_000 else { return self }
        let feeFraction = Decimal(bps) / Decimal(10_000)
        return FiatAmount(value: value / (1 - feeFraction), currency: currency)
    }

    /// The most of this balance that can be spent when the pool's sell fee is
    /// *grossed up* out of the spend: `balance × (1 − bps/10⁴)`, the inverse of
    /// `grossingUpLaunchpadSellFee(bps:)`.
    ///
    /// Grossing the result back up lands exactly on this balance, which makes it
    /// the largest entry the balance can fund. Unrounded, like its inverse —
    /// callers that need an entry-precision value floor it themselves.
    func spendableUnderGrossedUpSellFee(bps: UInt64) -> FiatAmount {
        let feeFraction = Decimal(min(bps, 10_000)) / Decimal(10_000)
        return FiatAmount(value: value * (1 - feeFraction), currency: currency)
    }

    /// The most of this balance that can be spent when the fee is charged *on
    /// top* of the spend rather than skimmed out of it: `balance / (1 + bps/10⁴)`.
    ///
    /// Adding that entry's own fee back lands exactly on this balance. Unrounded,
    /// for the same reason as `spendableUnderGrossedUpSellFee(bps:)`.
    func spendableUnderSellFeeOnTop(bps: UInt64) -> FiatAmount {
        let feeFraction = Decimal(min(bps, 10_000)) / Decimal(10_000)
        return FiatAmount(value: value / (1 + feeFraction), currency: currency)
    }
}
