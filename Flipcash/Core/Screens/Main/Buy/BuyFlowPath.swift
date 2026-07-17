//
//  BuyFlowPath.swift
//  Flipcash
//
//  Created by Raul Riera on 2026-05-12.
//

import Foundation
import FlipcashCore

/// Sub-flow path for the buy stack. The `.buy(mint)` sheet's root is
/// `BuyAmountScreen`; secondary screens (payment currency selection, buy
/// summary, post-buy processing) are pushed onto the same stack via
/// `router.pushAny(_:)`.
///
/// Modelled as a Hashable enum (not `AppRouter.Destination` cases) because the
/// associated values include `ExchangedFiat`, `VerifiedState` and `SwapId` —
/// all already Hashable + Sendable. Keeping these out of `Destination` matches
/// the `WithdrawNavigationPath` pattern.
enum BuyFlowPath: Hashable, Sendable {
    case selectPaymentCurrency(targetMint: PublicKey, targetName: String, entered: FiatAmount)
    case paymentConfirmation(
        targetMint: PublicKey,
        targetName: String,
        payment: StoredBalance,
        paymentAmount: ExchangedFiat,
        pinnedState: VerifiedState
    )
    case processing(swapId: SwapId, currencyName: String, amount: ExchangedFiat, swapType: SwapType)
}
