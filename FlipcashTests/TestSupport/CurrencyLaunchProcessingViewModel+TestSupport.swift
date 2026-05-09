//
//  CurrencyLaunchProcessingViewModel+TestSupport.swift
//  FlipcashTests
//

@testable import Flipcash

extension CurrencyLaunchProcessingViewModel {
    @MainActor
    func setDisplayStateForTesting(_ state: DisplayState) {
        displayState = state
    }
}
