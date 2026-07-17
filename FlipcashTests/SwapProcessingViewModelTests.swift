//
//  SwapProcessingViewModelTests.swift
//  FlipcashTests
//

import Foundation
import Testing
@testable import Flipcash
import FlipcashCore

@Suite("SwapProcessingViewModel — SwapType surface")
@MainActor
struct SwapProcessingViewModelTests {

    @Test("SwapType exposes the reserves, currency-paid, launch, and sell cases")
    func swapType_exposesExpectedCases() {
        #expect(SwapType.allCases.count == 4)
        #expect(SwapType.allCases.contains(.buyWithReserves))
        #expect(SwapType.allCases.contains(.buyWithCurrency))
        #expect(SwapType.allCases.contains(.launchWithReserves))
        #expect(SwapType.allCases.contains(.sell))
    }

    @Test("Processing navigation title reads the trimmed switch for every remaining case")
    func navigationTitle_processing_perSwapType() {
        func makeViewModel(_ type: SwapType) -> SwapProcessingViewModel {
            SwapProcessingViewModel(
                swapId: .generate(),
                swapType: type,
                currencyName: "TestCoin",
                amount: .mockOne
            )
        }
        #expect(makeViewModel(.buyWithReserves).navigationTitle == "Purchasing TestCoin")
        #expect(makeViewModel(.buyWithCurrency).navigationTitle == "Purchasing TestCoin")
        #expect(makeViewModel(.launchWithReserves).navigationTitle == "Purchasing TestCoin")
        #expect(makeViewModel(.sell).navigationTitle == "Selling TestCoin")
    }
}
