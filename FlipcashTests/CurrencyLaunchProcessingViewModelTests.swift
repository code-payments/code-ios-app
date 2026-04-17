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
        currencyName: String = "Test Coin",
        fundingMethod: CurrencyLaunchProcessingViewModel.FundingMethod = .reserves
    ) -> CurrencyLaunchProcessingViewModel {
        CurrencyLaunchProcessingViewModel(
            swapId: .generate(),
            launchedMint: .usdf,
            currencyName: currencyName,
            launchAmount: ExchangedFiat(underlying: 10_00_00, converted: 10_00_00, mint: .usdf),
            fundingMethod: fundingMethod
        )
    }

    @Test("Processing state copy")
    func processingCopy() {
        let vm = makeViewModel()
        #expect(vm.navigationTitle == "Creating Test Coin")
        #expect(vm.title == "This Will Take a Minute")
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
        #expect(vm.actionTitle == "Receive My Test Coin")
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

    @Test("Funding method maps to analytics event")
    func fundingAnalyticsEvent() {
        #expect(makeViewModel(fundingMethod: .reserves).analyticsEvent == .launchWithReserves)
        #expect(makeViewModel(fundingMethod: .phantom).analyticsEvent == .launchWithPhantom)
        #expect(makeViewModel(fundingMethod: .coinbase).analyticsEvent == .launchWithCoinbase)
    }
}
