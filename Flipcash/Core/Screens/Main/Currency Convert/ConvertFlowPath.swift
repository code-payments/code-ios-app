//
//  ConvertFlowPath.swift
//  Flipcash
//

import Foundation
import FlipcashCore

/// Sub-flow path for the convert stack. `ConvertAmountScreen` is the pushed
/// `.convertCurrency(mint)` destination; the confirmation and processing
/// screens are pushed onto the same host stack via `router.pushAny(_:)`.
///
/// Modelled as a Hashable enum (not `AppRouter.Destination` cases) because the
/// associated values include `ExchangedFiat`, `VerifiedState` and `SwapId` —
/// all already Hashable + Sendable. Mirrors `BuyFlowPath`.
enum ConvertFlowPath: Hashable, Sendable {
    case confirmation(
        sourceMint: PublicKey,
        destinationMint: PublicKey,
        destinationName: String,
        amount: ExchangedFiat,
        sellFeeBps: Int?,
        pinnedState: VerifiedState
    )
    case processing(swapId: SwapId, destinationMint: PublicKey, destinationName: String, amount: ExchangedFiat)
}
