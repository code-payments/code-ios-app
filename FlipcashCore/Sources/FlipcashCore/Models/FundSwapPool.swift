//
//  FundSwapPool.swift
//  FlipcashCore
//

import Foundation

/// The liquidity pool a client-built USDC→USDF funding swap routes through.
public enum FundSwapPool: Equatable, Sendable {
    /// The legacy Flipcash USDF liquidity pool.
    case usdf(LiquidityPool)
    /// The Coinbase Stable Swapper pool; `feeRecipient` is read from the
    /// on-chain pool account.
    case coinbaseStableSwapper(feeRecipient: PublicKey)
}
