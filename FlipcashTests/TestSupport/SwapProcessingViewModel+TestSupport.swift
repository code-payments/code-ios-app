//
//  SwapProcessingViewModel+TestSupport.swift
//  FlipcashTests
//

@testable import Flipcash
import FlipcashCore

extension SwapProcessingViewModel {
    func setDisplayStateForTesting(_ state: DisplayState, amount: ExchangedFiat? = nil) {
        if let amount {
            exchangedFiat = amount
        }
        displayState = state
    }
}
