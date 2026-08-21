//
//  FeeAffordableEntry.swift
//  FlipcashCore
//

import Foundation

/// Trims an entered amount down to what its funding `balance` can actually cover
/// once the fee is applied.
///
/// Amount entry is capped at the raw balance, so the only thing that can push the
/// debit past it is the fee: charged on top, the debit is `entered × (1 + f)`;
/// grossed up out of a launchpad sale, it is `entered / (1 − f)`. Entering the
/// maximum therefore always overruns — by the fee, and never by more — which is
/// why the correction is applied silently instead of being put to the user.
///
/// Returns the corrected entry, floored to the currency's smallest unit so
/// re-deriving the debit from it never lands back over the balance, or `nil` when
/// the entry already fits and should stay exactly as typed. `entered` is
/// interpreted in `balance`'s currency.
public func entryAffordableAfterFee(
    entered: Decimal,
    balance: FiatAmount,
    feeBps: UInt64,
    feeChargedOnTop: Bool
) -> FiatAmount? {
    guard feeBps > 0 else { return nil }

    let entry = FiatAmount(value: entered, currency: balance.currency)
    let feeFraction = Decimal(min(feeBps, 10_000)) / Decimal(10_000)

    // The fee has no fiat-only helper of its own — on `ExchangedFiat` it is
    // scaled by the on-chain quark ratio, which an entry-level check must not
    // depend on — so the on-top debit is spelled out here.
    let debit = feeChargedOnTop
        ? FiatAmount(value: entry.value * (1 + feeFraction), currency: balance.currency)
        : entry.grossingUpLaunchpadSellFee(bps: feeBps)
    guard debit > balance else { return nil }

    let spendable = feeChargedOnTop
        ? balance.spendableUnderSellFeeOnTop(bps: feeBps)
        : balance.spendableUnderGrossedUpSellFee(bps: feeBps)
    return spendable.flooredToSmallestUnit()
}
