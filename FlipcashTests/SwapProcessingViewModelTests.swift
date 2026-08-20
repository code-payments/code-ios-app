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

    @Test("SwapType exposes the reserves, currency-paid, sell, and convert cases")
    func swapType_exposesExpectedCases() {
        #expect(SwapType.allCases.count == 4)
        #expect(SwapType.allCases.contains(.buyWithReserves))
        #expect(SwapType.allCases.contains(.buyWithCurrency))
        #expect(SwapType.allCases.contains(.sell))
        #expect(SwapType.allCases.contains(.convert))
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
        #expect(makeViewModel(.buyWithReserves).navigationTitle == "Buying TestCoin")
        #expect(makeViewModel(.buyWithCurrency).navigationTitle == "Buying TestCoin")
        #expect(makeViewModel(.sell).navigationTitle == "Selling TestCoin")
        // Convert spans two currencies, so the title names neither.
        #expect(makeViewModel(.convert).navigationTitle == "Converting")
    }
}
