//
//  ExternalSwapProcessing.swift
//  Code
//

import FlipcashCore

/// Data required to render the processing screen for an external wallet swap.
struct ExternalSwapProcessing: Identifiable, Hashable {
    let swapId: SwapId
    let currencyName: String
    let amount: ExchangedFiat

    var id: String { swapId.publicKey.base58 }
}
