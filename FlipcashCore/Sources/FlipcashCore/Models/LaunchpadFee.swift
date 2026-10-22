//
//  LaunchpadFee.swift
//  FlipcashCore
//

import Foundation

/// Fee rates the client applies when converting or buying.
///
/// Two different fees are in play and they must not share a literal: the
/// fee Dollars pay when they fund a convert/buy, and the fallback rate for a
/// token pool's sell fee when the pool doesn't report one.
public enum LaunchpadFee {

    /// The fee, in basis points, charged on top when Dollars (USDF) fund a
    /// convert or buy. Zero makes those flows fee-free; a non-zero value
    /// restores the on-top fee (the debit becomes `amount + fee`, and the fee is
    /// split off on-chain via `TransferForSwapWithFee`).
    public static let dollarsFeeBps: UInt64 = 0

    /// The sell fee, in basis points, assumed for a token pool that doesn't
    /// report its own `sellFeeBps` (100 = 1%). Mirrors Android's
    /// `HOUSE_SELL_FEE_BPS`.
    public static let houseSellFeeBps: Int = 100

    /// `sellFeeBps` when the pool reported one, otherwise `houseSellFeeBps`,
    /// clamped to be non-negative.
    public static func poolSellFeeBps(_ sellFeeBps: Int?) -> UInt64 {
        UInt64(max(0, sellFeeBps ?? houseSellFeeBps))
    }
}
