//
//  BuyFlowPath.swift
//  Flipcash
//
//  Created by Raul Riera on 2026-05-12.
//

import Foundation
import FlipcashCore

/// Sub-flow path for the buy stack. The `.buy(mint)` sheet's root is
/// `BuyAmountScreen`; secondary screens (buy summary, post-buy processing) are
/// pushed onto the same stack via `router.pushAny(_:)`. Payment-source
/// selection is inline on the amount screen, so Next pushes the summary directly.
///
/// Modelled as a Hashable enum (not `AppRouter.Destination` cases) because the
/// associated values include `ExchangedFiat`, `VerifiedState` and `SwapId` —
/// all already Hashable + Sendable. Keeping these out of `Destination` matches
/// the `WithdrawNavigationPath` pattern.
enum BuyFlowPath: Hashable, Sendable {
    case paymentConfirmation(
        targetMint: PublicKey,
        targetName: String,
        payment: StoredBalance,
        paymentAmount: ExchangedFiat,
        pinnedState: VerifiedState
    )
    case processing(swapId: SwapId, targetMint: PublicKey, currencyName: String, amount: ExchangedFiat, swapType: SwapType)
}
