//
//  PaymentRequestPaymentCurrencyTests.swift
//  FlipcashTests
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("PaymentRequestPayment currency selection")
struct PaymentRequestPaymentCurrencyTests {

    @Test("Picking a currency on the pay sheet becomes the user's selection for every send flow")
    func selectCurrency_writesUserPickBack() throws {
        let container = try SessionContainer.makeTest(holdings: [
            SessionContainer.Holding(mint: .usdf, quarks: 100_000_000_000),
            SessionContainer.Holding(
                mint: .makeLaunchpad(address: .jeffy, supplyFromBonding: 1_000_000 * 10_000_000_000),
                quarks: 10 * 10_000_000_000
            ),
        ])
        defer { container.ratesController.selectedTokenMint = nil }
        container.ratesController.selectToken(.usdf, source: .automatic)
        let payment = PaymentRequestPayment(
            requestID: PaymentRequestID(data: Data([1])),
            sessionContainer: container
        )
        #expect(payment.selectedBalance?.stored.mint == .jeffy)

        let dollars = try #require(container.session.balances(
            for: container.ratesController.rateForBalanceCurrency()
        ).first { $0.stored.mint == .usdf })
        payment.selectCurrencyAction(exchangedBalance: dollars)

        #expect(payment.selectedBalance?.stored.mint == .usdf)
        #expect(container.ratesController.selectedTokenMint == .usdf)
        #expect(container.ratesController.isSelectedTokenUserPicked)
    }

    @Test("The pay and send pickers list the same balances, in the same order, as group send's")
    func paymentOptions_matchGroupSend() throws {
        let container = try SessionContainer.makeTest(holdings: [
            SessionContainer.Holding(mint: .usdf, quarks: 100_000_000_000),
            SessionContainer.Holding(
                mint: .makeLaunchpad(address: .jeffy, supplyFromBonding: 1_000_000 * 10_000_000_000),
                quarks: 10 * 10_000_000_000
            ),
        ])
        defer { container.ratesController.selectedTokenMint = nil }
        let groupSend = GroupSendViewModel(
            sessionContainer: container,
            conversationID: ConversationID(data: Data(repeating: 0x0B, count: 32))
        )
        let payment = PaymentRequestPayment(
            requestID: PaymentRequestID(data: Data([1])),
            sessionContainer: container
        )
        let send = SendAmountViewModel(
            sessionContainer: container,
            target: .contact(SendAmountViewModelTests.makeContact()),
            mint: nil
        )

        let expected = groupSend.paymentOptions.map(\.stored.mint)
        #expect(Set(expected) == [.usdf, .jeffy])
        #expect(payment.paymentOptions.map(\.stored.mint) == expected)
        #expect(send.paymentOptions.map(\.stored.mint) == expected)
    }
}

@MainActor
@Suite("PaymentRequestPayment without a balance")
struct PaymentRequestPaymentNoBalanceTests {

    @Test("The pay flow shows No Balance Yet and does not open the sheet when nothing is held")
    func start_noBalance_blocksSheet() async throws {
        let container = try SessionContainer.makeTest(holdings: [])
        let flow = PaymentRequestPayFlow()

        let result = await flow.start(
            PaymentRequestID(data: Data([1])),
            sessionContainer: container,
            router: AppRouter()
        )

        #expect(result == .noBalance)
        #expect(flow.isPaying == false)
        #expect(flow.payment == nil)
        #expect(container.session.dialogItem?.title == "No Balance Yet")
    }

    @Test("Submitting with no selected balance shows insufficient funds, not Couldn't Send")
    func submit_nilSelectedBalance_showsInsufficientFunds() async throws {
        let container = try SessionContainer.makeTest(holdings: [])
        let payment = PaymentRequestPayment(
            requestID: PaymentRequestID(data: Data([1])),
            sessionContainer: container
        )
        #expect(payment.selectedBalance == nil)

        let outcome = await payment.submit()

        #expect(outcome == .failed)
        #expect(container.session.dialogItem?.title == "You Need More Cash")
    }
}
