//
//  InsufficientFundsSheetTests.swift
//  FlipcashTests
//

import Foundation
import Testing
import FlipcashCore
import FlipcashUI
@testable import Flipcash

@MainActor
@Suite("Insufficient funds over a swipe sheet")
struct InsufficientFundsSheetTests {

    // MARK: - Currency Info send

    @Test("Add More Cash on a short Currency Info send routes to the deposit for the sent currency")
    func currencySendAddMoney() async {
        let mock = MockSession()
        let viewModel = SendAmountViewModel(
            sessionContainer: .mock,
            target: .contact(SendAmountViewModelTests.makeContact()),
            mint: nil,
            sender: mock,
            resolver: mock
        )
        viewModel.selectCurrencyAction(exchangedBalance: ExchangedBalance.makeTest(quarks: 0))
        viewModel.enteredAmount = "5"

        #expect(await viewModel.sendAction() == .failed)
        let dialog = viewModel.session.dialogItem
        let add = dialog?.actions.first { $0.title == "Add More Cash" }
        #expect(add != nil)
        add?.perform(isChecked: false)

        #expect(viewModel.depositMint == viewModel.selectedBalance?.stored.mint)
        #expect(viewModel.depositMint != nil)
    }
}
