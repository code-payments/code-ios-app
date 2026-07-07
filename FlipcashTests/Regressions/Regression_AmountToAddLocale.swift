//
//  Regression_AmountToAddLocale.swift
//  FlipcashTests
//
//  The "Amount to Add" screen binds `KeyPadView`, whose decimal key emits
//  `AmountValidator.localizedDecimalSeparator`. On comma-decimal locales the
//  bound string contains ",". Parsing it with `Decimal(string:)` stops at the
//  comma and silently drops the fraction on a real-money deposit (the PR #448
//  bug). `AddMoneyAmountViewModel` MUST parse through `AmountValidator`.
//

import Foundation
import Testing
@testable import Flipcash
@testable import FlipcashCore

@Suite("Regression: Amount to Add – comma-locale keypad input keeps its fraction")
@MainActor
struct Regression_AmountToAddLocale {

    private static let sendLimit = SendLimit(
        nextTransaction: FiatAmount(value: 1000, currency: .usd),
        maxPerTransaction: FiatAmount(value: 1000, currency: .usd),
        maxPerDay: FiatAmount(value: 1000, currency: .usd)
    )

    /// A comma-decimal keypad string ("1,50") must parse as 1.50, not 1 — the
    /// view model parses via `AmountValidator` (comma separator canonicalised
    /// to "."), never `Decimal(string:)`, which drops the fraction at the comma.
    @Test("Comma-decimal entry parses as 1.50, not 1")
    func commaDecimalEntry_keepsFraction() throws {
        let container = try SessionContainer.makeTest(
            holdings: [],
            limits: Limits(sinceDate: .now, fetchDate: .now, sendLimits: [.usd: Self.sendLimit])
        )
        container.ratesController.configureTestRates(
            balanceCurrency: .usd,
            rates: [Rate(fx: 1.0, currency: .usd)]
        )

        let viewModel = AddMoneyAmountViewModel(
            method: .otherWallet,
            session: container.session,
            ratesController: container.ratesController,
            amountValidator: AmountValidator(separator: ",")
        )

        viewModel.enteredAmount = "1,50"

        let fiat = try #require(viewModel.enteredFiat)
        #expect(fiat.nativeAmount.value == Decimal(string: "1.5"))
    }
}
