//
//  Regression_69f39bbb.swift
//  Flipcash
//
//  Submitted withdrawal quarks must never exceed the on-chain balance.
//  Display rounding (`.halfUp` formatter) and `Decimal.scaleUpInt` HALF_UP
//  rounding can both push the round-trip "entered fiat → quarks" 1+ quarks
//  above balance, which the server rejects as
//  `actions[0]: <vault> has insufficient balance to perform action`.
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("Regression: 69f39bbb – Withdraw clamps submitted quarks to on-chain balance",
       .bug("69f39bbb0174c5d91b080000"))
struct Regression_69f39bbb {

    /// Two USDF balances whose displayed max rounds .halfUp to the next
    /// currency unit:
    ///   - 99_995_000 quarks → 99.995 USDF → "$100.00"
    ///   - 99_999_999 quarks → 99.999999 USD → 136.9999... CAD → "$137.00"
    @Test("USDF withdraw: displayed max rounds up — submission clamps to balance",
          arguments: [
              (quarks: UInt64(99_995_000), currency: CurrencyCode.usd, fx: 1.0, enteredAmount: "100.00"),
              (quarks: UInt64(99_999_999), currency: CurrencyCode.cad, fx: 1.37, enteredAmount: "137.00"),
          ])
    func usdfWithdraw_displayRoundsUp_clampsToBalance(
        quarks: UInt64,
        currency: CurrencyCode,
        fx: Double,
        enteredAmount: String
    ) async throws {
        let (sessionContainer, balance) = try WithdrawViewModelTestHelpers.makeUSDFFixture(
            quarks: quarks
        )
        let rate = Rate(fx: Decimal(fx), currency: currency)
        sessionContainer.ratesController.configureTestRates(
            entryCurrency: currency,
            rates: [rate]
        )
        await sessionContainer.ratesController.verifiedProtoService.saveRates([
            .freshRate(currencyCode: currency.rawValue.uppercased(), rate: fx)
        ])

        let viewModel = WithdrawViewModel(container: .mock, sessionContainer: sessionContainer)
        viewModel.kind = .sameMint(balance)
        viewModel.enteredAmount = enteredAmount

        let submission = try #require(await viewModel.prepareSubmission())

        #expect(submission.amount.onChainAmount.quarks <= balance.stored.quarks)
    }

    @Test("Bonded withdraw: rounding overshoot clamps to on-chain balance")
    func bondedWithdraw_roundingOvershoot_clampsToBalance() async throws {
        // Live and pinned supply match so the bug isolates rounding, not drift.
        let supply: UInt64 = 1_000_000 * 10_000_000_000
        let bondedQuarks: UInt64 = 100 * 10_000_000_000

        let sessionContainer = try SessionContainer.makeTest(holdings: [
            .init(
                mint: .makeLaunchpad(address: .jeffy, supplyFromBonding: supply),
                quarks: bondedQuarks
            )
        ])
        sessionContainer.ratesController.configureTestRates(
            entryCurrency: .usd,
            rates: [.oneToOne]
        )
        await sessionContainer.ratesController.verifiedProtoService.saveRates([
            .freshRate(currencyCode: "USD", rate: 1.0)
        ])
        await sessionContainer.ratesController.verifiedProtoService.saveReserveStates([
            .freshReserve(mint: .jeffy, supplyFromBonding: supply)
        ])

        let stored = try #require(sessionContainer.session.balance(for: .jeffy))
        let balance = ExchangedBalance(
            stored: stored,
            exchangedFiat: stored.computeExchangedValue(with: .oneToOne)
        )

        let viewModel = WithdrawViewModel(container: .mock, sessionContainer: sessionContainer)
        viewModel.kind = .sameMint(balance)
        viewModel.enteredAmount = balance.exchangedFiat.nativeAmount.value.formatted()

        let submission = try #require(await viewModel.prepareSubmission())

        #expect(submission.amount.onChainAmount.quarks <= stored.quarks)
    }
}
