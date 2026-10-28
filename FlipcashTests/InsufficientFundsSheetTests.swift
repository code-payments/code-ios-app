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

    // MARK: - Request pay pre-check

    @Test("A share over the balance is insufficient before any swipe sheet, with an Add More Cash action")
    func overBalanceShare() async throws {
        let (payment, container) = try await makePayment(shareAmount: 150)

        #expect(await payment.affordability() == .insufficient)

        let dialog = try #require(container.session.dialogItem)
        #expect(dialog.actions.first?.title == "Add More Cash")
        dialog.actions[0].perform(isChecked: false)
        #expect(payment.depositMint == .usdf)
    }

    @Test("A share within the balance is sufficient and shows no dialog")
    func withinBalanceShare() async throws {
        let (payment, container) = try await makePayment(shareAmount: 20)

        #expect(await payment.affordability() == .sufficient)
        #expect(container.session.dialogItem == nil)
    }

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

    // MARK: - Helpers

    private func makePayment(shareAmount: Double) async throws -> (PaymentRequestPayment, SessionContainer) {
        let container = try await SendAmountViewModelTests.makeReadyToSendContainer()
        let id = PaymentRequestID(data: Data([7]))
        let creator = UUID()
        container.paymentRequests.ingest([
            GroupPaymentRequest(
                id: id,
                creator: creator,
                createdAt: .now,
                status: .open,
                closedAt: nil,
                version: 1,
                chatID: ConversationID.test(1),
                split: .init(
                    text: .plaintext(title: "Dinner", description: ""),
                    currency: "usd",
                    endsAt: .now.addingTimeInterval(3600),
                    shares: [
                        .init(userID: creator, nativeAmount: shareAmount, settlement: .creator),
                        .init(userID: container.session.userID, nativeAmount: shareAmount),
                    ]
                )
            )
        ])
        let payment = PaymentRequestPayment(requestID: id, sessionContainer: container)
        try #require(payment.selectedBalance != nil)
        return (payment, container)
    }
}
