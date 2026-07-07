//
//  AddMoneyAmountViewModelTests.swift
//  FlipcashTests
//

import Foundation
import Testing
@testable import FlipcashCore
@testable import Flipcash

@Suite("AddMoneyAmountViewModel — validation & gating")
@MainActor
struct AddMoneyAmountViewModelTests {

    private static let testSendLimit = SendLimit(
        nextTransaction: FiatAmount(value: 1000, currency: .usd),
        maxPerTransaction: FiatAmount(value: 1000, currency: .usd),
        maxPerDay: FiatAmount(value: 1000, currency: .usd)
    )

    private static func makeContainer() throws -> SessionContainer {
        let container = try SessionContainer.makeTest(
            holdings: [],
            limits: Limits(sinceDate: .now, fetchDate: .now, sendLimits: [.usd: testSendLimit])
        )
        container.ratesController.configureTestRates(
            balanceCurrency: .usd,
            rates: [Rate(fx: 1.0, currency: .usd)]
        )
        return container
    }

    private static func makeViewModel(
        method: DepositMethod = .coinbase,
        amountValidator: AmountValidator = AmountValidator(),
        container: SessionContainer
    ) -> AddMoneyAmountViewModel {
        AddMoneyAmountViewModel(
            method: method,
            session: container.session,
            ratesController: container.ratesController,
            amountValidator: amountValidator
        )
    }

    @Test("Entered amount is parsed through AmountValidator into the native fiat")
    func enteredFiat_parsesViaAmountValidator() throws {
        let container = try Self.makeContainer()
        let viewModel = Self.makeViewModel(container: container)

        viewModel.enteredAmount = "12.50"
        let fiat = try #require(viewModel.enteredFiat)
        #expect(fiat.nativeAmount.value == Decimal(string: "12.50"))
        #expect(fiat.nativeAmount.currency == .usd)
    }

    @Test(
        "canAdd gates on a valid amount within the send limit",
        arguments: [
            (entered: "", expected: false),
            (entered: "50", expected: true),
            (entered: "2000", expected: false),
        ]
    )
    func canAdd_gatesOnLimitAndValidity(entered: String, expected: Bool) throws {
        let container = try Self.makeContainer()
        let viewModel = Self.makeViewModel(container: container)

        viewModel.enteredAmount = entered
        #expect(viewModel.canAdd == expected)
    }

    @Test("A comma-decimal keypad string parses the fraction instead of dropping it")
    func enteredFiat_commaLocale_parsesFraction() throws {
        let container = try Self.makeContainer()
        let viewModel = Self.makeViewModel(
            amountValidator: AmountValidator(separator: ","),
            container: container
        )

        viewModel.enteredAmount = "12,50"
        let fiat = try #require(viewModel.enteredFiat)
        #expect(fiat.nativeAmount.value == Decimal(string: "12.50"))
    }

    @Test(
        "The action CTA is method-specific — Phantom signs in-wallet, Coinbase adds money",
        arguments: [
            (method: DepositMethod.coinbase, title: "Add Money"),
            (method: DepositMethod.phantom, title: "Confirm in Phantom"),
        ]
    )
    func actionTitle_isMethodSpecific(method: DepositMethod, title: String) throws {
        let container = try Self.makeContainer()
        let viewModel = Self.makeViewModel(method: method, container: container)
        #expect(viewModel.actionTitle == title)
    }
}
