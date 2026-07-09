//
//  AddMoneyProcessingInput.swift
//  Flipcash
//

import Foundation
import FlipcashCore

/// Everything the blocking "Adding Money" screen needs to observe settlement.
struct AddMoneyProcessingInput: Hashable, Sendable {
    let amount: ExchangedFiat
    let method: DepositMethod
    /// Operation identifier for log correlation — the Coinbase order id or
    /// the Phantom transaction signature.
    let depositRef: String?
}
