//
//  ExternalLaunchProcessing.swift
//  Flipcash
//

import FlipcashCore

/// Data required to render `CurrencyLaunchProcessingScreen` after an external
/// wallet (Phantom) signs a currency-launch funding transaction. Distinct from
/// `ExternalSwapProcessing` so buy-existing and launch flows don't share a
/// hybrid shape.
struct ExternalLaunchProcessing: Identifiable, Hashable {
    let swapId: SwapId
    let launchedMint: PublicKey
    let currencyName: String
    let amount: ExchangedFiat

    var id: String { swapId.publicKey.base58 }
}
