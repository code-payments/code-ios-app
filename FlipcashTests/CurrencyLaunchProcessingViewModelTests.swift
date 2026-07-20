//
//  CurrencyLaunchProcessingViewModelTests.swift
//  FlipcashTests
//

import Testing
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("CurrencyLaunchProcessingViewModel")
struct CurrencyLaunchProcessingViewModelTests {

    private func makeViewModel(
        currencyName: String = "Test Coin"
    ) -> CurrencyLaunchProcessingViewModel {
        CurrencyLaunchProcessingViewModel(
            swapId: .generate(),
            launchedMint: .usdf,
            currencyName: currencyName,
            launchAmount: ExchangedFiat.mockOne,
            paymentMint: .usdf
        )
    }

    @Test("Processing state copy")
    func processingCopy() {
        let vm = makeViewModel()
        #expect(vm.navigationTitle == "Creating Test Coin")
        #expect(vm.title == "This Will Take a Few Minutes")
        #expect(vm.subtitle == "This transaction typically takes a few minutes. You may leave the app while it completes")
        #expect(vm.actionTitle == "Notify Me When Complete")
    }

    @Test("Success state copy")
    func successCopy() {
        let vm = makeViewModel()
        vm.setDisplayStateForTesting(.success)
        #expect(vm.navigationTitle == "Success")
        #expect(vm.title == "Test Coin Is Live")
        #expect(vm.subtitle == "Your currency is ready to receive and use")
        #expect(vm.actionTitle == "Get The First $1 of Your Currency Free")
    }

    @Test("Failed state copy")
    func failedCopy() {
        let vm = makeViewModel()
        vm.setDisplayStateForTesting(.failed)
        #expect(vm.navigationTitle == "Transaction Failed")
        #expect(vm.title == "Something Went Wrong")
        #expect(vm.subtitle == "Please try again later")
        #expect(vm.actionTitle == "OK")
    }

}
