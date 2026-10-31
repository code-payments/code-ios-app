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
}
