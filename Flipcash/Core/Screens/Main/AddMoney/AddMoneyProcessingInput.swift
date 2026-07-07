//
//  AddMoneyProcessingInput.swift
//  Flipcash
//

import Foundation
import FlipcashCore

/// Everything the blocking "Adding Money" screen needs to observe settlement:
/// the deposited amount (to detect the USDF balance rise) and which method
/// produced it (Coinbase/Other Wallet require a USDC→USDF sweep first; Phantom
/// already submitted the swap on chain).
struct AddMoneyProcessingInput: Hashable, Sendable {
    let amount: ExchangedFiat
    let method: DepositMethod
}
