//
//  Regression_max_entry_display_parse.swift
//  Flipcash
//
//  Bug: entering the displayed maximum turned the "Enter up to $8.54" subtitle
//       red and disabled Next, so the full balance could not be withdrawn.
//
//  Cause: isWithinDisplayLimit compared the entry against the max round-tripped
//         through NumberFormatter.number(from:), which yields a double-derived
//         NSNumber even with generatesDecimalNumbers set — "$8.54" parses back
//         as 8.539999999999999, putting an exact 8.54 entry over the cap. 85 of
//         the first 2000 cent values land on such a value.
//
//  Fix: derive the display cap by rounding the max with Decimal arithmetic
//       instead of formatting it and parsing the string back.
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("Regression: entering the displayed maximum is accepted")
struct Regression_max_entry_display_parse {

    @Test("The reported case: $8.54 entered against an $8.54 cap")
    func reportedCase_usd854() {
        let max = FiatAmount(value: Decimal(string: "8.54")!, currency: .usd)
        #expect(EnterAmountCalculator.isWithinDisplayLimit(enteredAmount: "8.54", max: max) == true)
    }

    @Test("Every cent value up to $20 accepts its own displayed maximum")
    func everyCentValue_acceptsItsOwnDisplayedMax() {
        let rejected: [String] = (1...2_000).compactMap { cents in
            let max = FiatAmount(value: Decimal(cents) / 100, currency: .usd)
            let entered = AmountValidator(separator: ".").string(from: max.value, fractionDigits: 2)
            let accepted = EnterAmountCalculator.isWithinDisplayLimit(enteredAmount: entered, max: max)
            return accepted ? nil : entered
        }

        #expect(rejected.isEmpty, "displayed maximums rejected: \(rejected)")
    }

    @Test("A cent above the displayed maximum is still rejected")
    func oneCentOver_isRejected() {
        let max = FiatAmount(value: Decimal(string: "8.54")!, currency: .usd)
        #expect(EnterAmountCalculator.isWithinDisplayLimit(enteredAmount: "8.55", max: max) == false)
    }

    @Test("Withdraw: the full balance keeps Next enabled")
    func withdraw_atFullBalance_canProceed() throws {
        // $8.54 of USDF — the balance in the report.
        let (container, usdf) = try WithdrawViewModelTestHelpers.makeUSDFFixture(quarks: 8_540_000)
        let viewModel = WithdrawViewModel(container: .mock, sessionContainer: container)
        viewModel.kind = .usdfToUsdc(usdf)
        viewModel.enteredAmount = "8.54"

        #expect(viewModel.canProceedToAddress == true)
    }
}
