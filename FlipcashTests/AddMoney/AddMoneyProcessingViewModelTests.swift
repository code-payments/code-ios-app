//
//  AddMoneyProcessingViewModelTests.swift
//  FlipcashTests
//

import Foundation
import Testing
@testable import Flipcash
import FlipcashCore

@Suite("AddMoneyProcessingViewModel — settlement state machine")
@MainActor
struct AddMoneyProcessingViewModelTests {

    // MARK: - Fixtures

    /// $10 USDF-denominated deposit (USDF uses 6 decimals → 10_000_000 quarks).
    private static let tenDollars = ExchangedFiat(
        onChainAmount: TokenAmount(quarks: 10_000_000, mint: .usdf),
        nativeAmount: .usd(10),
        currencyRate: .oneToOne
    )

    private static func usdfBalance(dollars: Decimal) throws -> StoredBalance {
        try StoredBalance(
            quarks: TokenAmount(wholeTokens: dollars, mint: .usdf).quarks,
            symbol: "USDF",
            name: "USDF",
            supplyFromBonding: nil,
            sellFeeBps: nil,
            mint: .usdf,
            vmAuthority: nil,
            updatedAt: .now,
            imageURL: nil,
            costBasis: 0
        )
    }

    private static func makeViewModel(method: DepositMethod) -> AddMoneyProcessingViewModel {
        AddMoneyProcessingViewModel(
            input: AddMoneyProcessingInput(amount: tenDollars, method: method, depositRef: nil),
            pollInterval: .milliseconds(1),
            timeout: .milliseconds(200)
        )
    }

    // MARK: - Fakes

    /// Controllable USDF balance. `updateBalance()` swaps in `risenBalance`
    /// once `updateCount` reaches `risesAfterUpdates`, simulating a Geyser credit
    /// arriving after a server refresh.
    final class FakeAddMoneySettling: AddMoneySettling {
        var usdfBalance: StoredBalance?
        var risenBalance: StoredBalance?
        var risesAfterUpdates: Int = .max
        private(set) var updateCount = 0

        func balance(for mint: PublicKey) -> StoredBalance? {
            mint == .usdf ? usdfBalance : nil
        }

        func updateBalance() {
            updateCount += 1
            if updateCount >= risesAfterUpdates, let risenBalance {
                usdfBalance = risenBalance
            }
        }
    }

    final class SweepSpy {
        private(set) var called = false
        func markCalled() { called = true }
    }

    // MARK: - Success on balance rise

    @Test("Coinbase deposit sweeps then reaches success once USDF rises")
    func run_coinbase_sweepsThenSucceedsOnBalanceRise() async throws {
        let viewModel = Self.makeViewModel(method: .coinbase)
        let settlement = FakeAddMoneySettling()
        settlement.risenBalance = try Self.usdfBalance(dollars: 10)
        settlement.risesAfterUpdates = 1
        let spy = SweepSpy()

        await viewModel.run(settlement: settlement) {
            spy.markCalled()
            return true
        }

        #expect(spy.called)
        #expect(viewModel.isSuccess)
        #expect(viewModel.displayState == .success)
    }

    @Test("Phantom deposit skips the sweep and succeeds on balance rise")
    func run_phantom_skipsSweepAndSucceeds() async throws {
        let viewModel = Self.makeViewModel(method: .phantom)
        let settlement = FakeAddMoneySettling()
        settlement.risenBalance = try Self.usdfBalance(dollars: 10)
        settlement.risesAfterUpdates = 1
        let spy = SweepSpy()

        await viewModel.run(settlement: settlement) {
            spy.markCalled()
            return true
        }

        #expect(!spy.called)
        #expect(viewModel.isSuccess)
    }

    // MARK: - Failure on timeout

    @Test("A USDF balance that never rises times out into the failed state")
    func run_whenBalanceNeverRises_failsOnTimeout() async throws {
        let viewModel = Self.makeViewModel(method: .coinbase)
        let settlement = FakeAddMoneySettling() // baseline nil → 0, never rises

        await viewModel.run(settlement: settlement) { true }

        #expect(viewModel.displayState == .failed)
        #expect(!viewModel.isSuccess)
        #expect(viewModel.isFinished)
    }
}
