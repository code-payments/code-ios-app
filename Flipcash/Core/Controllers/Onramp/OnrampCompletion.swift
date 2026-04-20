//
//  OnrampCompletion.swift
//  Flipcash
//

import Foundation
import FlipcashCore

enum OnrampCompletion: Identifiable, Hashable {
    case buyProcessing(swapId: SwapId, currencyName: String, amount: ExchangedFiat)
    case launchProcessing(swapId: SwapId, launchedMint: PublicKey, currencyName: String, amount: ExchangedFiat)

    var id: String {
        switch self {
        case .buyProcessing(let swapId, _, _):
            "buy-\(swapId.publicKey.base58)"
        case .launchProcessing(let swapId, _, _, _):
            "launch-\(swapId.publicKey.base58)"
        }
    }
}
