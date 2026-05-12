//
//  BuyFlowPath.swift
//  Flipcash
//
//  Created by Raul Riera on 2026-05-12.
//

import Foundation
import FlipcashCore

/// Sub-flow path for the buy stack. The `.buy(mint)` sheet's root is
/// `BuyAmountScreen`; secondary screens (Phantom education/confirm, USDC
/// deposit education/address, post-buy processing) are pushed onto the same
/// stack via `router.pushAny(_:on:)`.
///
/// Modelled as a Hashable enum (not `AppRouter.Destination` cases) because the
/// associated values include `ExchangedFiat` and `SwapId` — both already
/// Hashable + Sendable. Keeping these out of `Destination` matches the
/// `WithdrawNavigationPath` pattern.
enum BuyFlowPath: Hashable {
    case phantomEducation(mint: PublicKey, amount: ExchangedFiat)
    case phantomConfirm(mint: PublicKey, amount: ExchangedFiat)
    case usdcDepositEducation(mint: PublicKey, amount: ExchangedFiat)
    case usdcDepositAddress(mint: PublicKey, amount: ExchangedFiat)
    case processing(swapId: SwapId, currencyName: String, amount: ExchangedFiat, swapType: SwapType)
}
