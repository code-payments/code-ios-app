//
//  CurrencyLaunchProcessingViewModel+TestSupport.swift
//  FlipcashTests
//

@testable import Flipcash

extension CurrencyLaunchProcessingViewModel {
    func setDisplayStateForTesting(_ state: DisplayState) {
        displayState = state
    }
}
