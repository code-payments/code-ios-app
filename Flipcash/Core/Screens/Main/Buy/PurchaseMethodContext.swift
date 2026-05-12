//
//  PurchaseMethodContext.swift
//  Flipcash
//
//  Created by Raul Riera on 2026-05-12.
//

import Foundation
import FlipcashCore

/// Snapshot of pinned submission state that travels from the amount-entry
/// screen into whichever funding branch the user picks (Apple Pay, Phantom,
/// Other Wallet). Carrying the pin avoids re-fetching the verified state at
/// each step and preserves the pin-at-compute invariant.
struct PurchaseMethodContext: Identifiable {
    let id = UUID()
    let mint: PublicKey
    let currencyName: String
    let amount: ExchangedFiat
    let verifiedState: VerifiedState
}
