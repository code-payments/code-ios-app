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
            paymentMint: .usdf,
            attemptsUsed: 0
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

    // MARK: - Inline window

    @Test("Inline wait: a failed swap stays in the wizard")
    func inlineFailure() async throws {
        let container = try SessionContainer.makeTest(holdings: [])
        let vm = makeViewModel()
        let outcome = await vm.awaitInline(session: container.session, ratesController: container.ratesController) { _, _ in .makeTest(state: .failed) }
        #expect(outcome == .failed)
    }

    @Test("Inline wait: a swap still in flight hands over to the processing screen with its budget reduced")
    func inlinePending() async throws {
        let container = try SessionContainer.makeTest(holdings: [])
        let vm = makeViewModel()
        let outcome = await vm.awaitInline(session: container.session, ratesController: container.ratesController) { attempts, interval in
            #expect(attempts == InlineCompletion.maxAttempts)
            #expect(interval == InlineCompletion.pollInterval)
            return .makeTest(state: .funding)
        }
        #expect(outcome == .pending)
        #expect(CurrencyLaunchProcessingViewModel.maxSwapAttempts - InlineCompletion.slowPathCredit == 115)
        #expect(SwapProcessingViewModel.maxAttempts - InlineCompletion.slowPathCredit == 85)
    }

    @Test("Balance budget shrinks by the inline window's time, not its poll count")
    func balanceBudgetIsTimeBased() {
        let vm = CurrencyLaunchProcessingViewModel(
            swapId: .generate(), launchedMint: .usdf, currencyName: "T",
            launchAmount: .mockOne, paymentMint: .usdf, attemptsUsed: InlineCompletion.slowPathCredit
        )
        #expect(vm.remainingBalanceAttempts == 58)
    }
}
