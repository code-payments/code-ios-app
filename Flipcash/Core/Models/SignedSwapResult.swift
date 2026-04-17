//
//  SignedSwapResult.swift
//  Flipcash
//

import FlipcashCore

/// Result returned from a signed external-funding callback (Phantom or Coinbase
/// onramp). The two cases are mutually exclusive — a buy of an existing currency
/// reports its swap id only, while a currency launch reports both the swap id
/// and the newly-created mint so the caller can present the launch processing
/// screen and hand off to a cash bill.
enum SignedSwapResult {
    case buyExisting(swapId: SwapId)
    case launch(swapId: SwapId, mint: PublicKey)

    var swapId: SwapId {
        switch self {
        case .buyExisting(let id), .launch(let id, _): id
        }
    }
}
