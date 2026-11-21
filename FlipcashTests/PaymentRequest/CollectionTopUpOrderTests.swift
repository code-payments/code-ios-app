//
//  CollectionTopUpOrderTests.swift
//  FlipcashTests
//

import Foundation
import Testing
@testable import Flipcash
@testable import FlipcashCore

@Suite("Collection top-up order outcome")
@MainActor
struct CollectionTopUpOrderTests {

    private static let rejected = DepositError.externalRejected(title: "Rejected", subtitle: "Try again")

    @Test("Before Apple Pay authorizes, nothing was charged", arguments: [
        ApplePayEvent.Event?.none, .loadError, .commitError, .pollingError,
    ])
    func beforeAuthorization(terminal: ApplePayEvent.Event?) {
        func ended(_ error: any Error, timedOut: Bool = false) -> CollectionTopUpOrder {
            CollectionTopUpOrder.ended(by: error, authorized: false, terminalError: terminal, timedOut: timedOut)
        }

        #expect(ended(CancellationError()) == .notCharged(.cancelled))
        #expect(ended(CancellationError(), timedOut: true) == .notCharged(.timedOut))
        #expect(ended(DepositError.userCancelled) == .notCharged(.cancelled))
        #expect(ended(Self.rejected) == .notCharged(.rejected(title: "Rejected", subtitle: "Try again")))
        #expect(ended(DepositError.unexpectedFailure(reason: "x")) == .notCharged(.failed))
    }

    @Test("After Apple Pay authorizes, anything but a commit error may still deliver", arguments: [
        ApplePayEvent.Event?.none, .loadError, .pollingError,
    ])
    func afterAuthorization(terminal: ApplePayEvent.Event?) {
        let errors: [any Error] = [
            CancellationError(), DepositError.userCancelled, Self.rejected, DepositError.unexpectedFailure(reason: "x"),
        ]
        for error in errors {
            #expect(CollectionTopUpOrder.ended(by: error, authorized: true, terminalError: terminal, timedOut: false) == .mayDeliver)
        }
        #expect(CollectionTopUpOrder.ended(by: CancellationError(), authorized: true, terminalError: terminal, timedOut: true) == .mayDeliver)
    }

    @Test("A commit error after Apple Pay authorizes is a known failure: nothing was bought")
    func commitErrorAfterAuthorization() {
        #expect(
            CollectionTopUpOrder.ended(by: Self.rejected, authorized: true, terminalError: .commitError, timedOut: false)
                == .notCharged(.rejected(title: "Rejected", subtitle: "Try again"))
        )
    }

    // MARK: - Amounts

    @Test("The $5 minimum in the request currency rounds up to its smallest unit", arguments: [
        (rate: Rate(fx: 1.0, currency: .usd), digits: 2, micros: Int64(5_000_000)),
        (rate: Rate(fx: 1.3712, currency: .cad), digits: 2, micros: Int64(6_860_000)),
        (rate: Rate(fx: 154.27, currency: .jpy), digits: 0, micros: Int64(772_000_000)),
    ])
    func minimumTopUp(_ c: (rate: Rate, digits: Int, micros: Int64)) {
        #expect(PaymentRequestPayment.minimumTopUpMicros(rate: c.rate, minorDigits: c.digits) == c.micros)
    }

    @Test("The USD order for a top-up rounds up to the cent, so it never buys less than the plan counted on", arguments: [
        (rate: Rate(fx: 1.0, currency: .usd), micros: Int64(12_040_000), usd: Decimal(string: "12.04")!),
        (rate: Rate(fx: 1.3712, currency: .cad), micros: Int64(6_860_000), usd: Decimal(string: "5.01")!),
        (rate: Rate(fx: 154.27, currency: .jpy), micros: Int64(772_000_000), usd: Decimal(string: "5.01")!),
    ])
    func orderUSD(_ c: (rate: Rate, micros: Int64, usd: Decimal)) {
        #expect(PaymentRequestPayment.topUpOrderUSD(topUpMicros: c.micros, rate: c.rate) == c.usd)
    }
}
