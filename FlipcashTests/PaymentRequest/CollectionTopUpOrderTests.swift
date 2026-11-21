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

@Suite("Collection top-up order lookup")
@MainActor
struct CollectionTopUpOrderLookupTests {

    @Test("A status Coinbase ends an undelivered order with reads as failed", arguments: [
        "ONRAMP_ORDER_STATUS_FAILED", "failed", "CANCELLED", "ONRAMP_ORDER_STATUS_EXPIRED", "DECLINED",
    ])
    func failedStatus(_ status: String) {
        #expect(OnrampOrderStatusResponse.isFailed(status: status))
    }

    @Test("A status for an order still running or delivered doesn't read as failed", arguments: [
        "ONRAMP_ORDER_STATUS_PENDING_AUTH", "ONRAMP_ORDER_STATUS_PENDING_PAYMENT",
        "ONRAMP_ORDER_STATUS_PROCESSING", "ONRAMP_ORDER_STATUS_COMPLETED", "",
    ])
    func notFailedStatus(_ status: String) {
        #expect(!OnrampOrderStatusResponse.isFailed(status: status))
    }

    @Test("An order read back decodes its status alone, with no payment link")
    func decodesWithoutPaymentLink() throws {
        let json = #"{"order":{"orderId":"cb-1","status":"ONRAMP_ORDER_STATUS_FAILED","txHash":null}}"#
        let response = try JSONDecoder().decode(OnrampOrderStatusResponse.self, from: Data(json.utf8))
        #expect(response.isFailed)
        #expect(response.order.txHash == nil)
    }

    @Test("The lookup is failed only when Coinbase reads the order back as failed")
    func lookupReadsFailed() async {
        let ordering = MockOnrampOrdering()
        ordering.orderStatusHandler = { _ in try Self.status("ONRAMP_ORDER_STATUS_FAILED") }
        #expect(await SessionCollectionTopUpper.orderFailed(orderID: "cb-1", ordering: ordering, timeout: .seconds(5)))
        #expect(ordering.orderStatusCalls == ["cb-1"])

        ordering.orderStatusHandler = { _ in try Self.status("ONRAMP_ORDER_STATUS_PROCESSING") }
        #expect(!(await SessionCollectionTopUpper.orderFailed(orderID: "cb-1", ordering: ordering, timeout: .seconds(5))))
    }

    @Test("A lookup that errors reads as not failed")
    func lookupErrorIsNotFailed() async {
        let ordering = MockOnrampOrdering()
        ordering.orderStatusHandler = { _ in throw Coinbase.Error.badStatus(code: 404, body: Data()) }
        #expect(!(await SessionCollectionTopUpper.orderFailed(orderID: "cb-1", ordering: ordering, timeout: .seconds(5))))
    }

    @Test("A lookup that never answers reads as not failed at its timeout", .timeLimit(.minutes(1)))
    func lookupNeverAnswersIsNotFailed() async {
        let ordering = MockOnrampOrdering()
        ordering.orderStatusHandler = { _ in
            try await Task.sleep(for: .seconds(3600))
            return try Self.status("ONRAMP_ORDER_STATUS_FAILED")
        }
        let started = ContinuousClock.now
        #expect(!(await SessionCollectionTopUpper.orderFailed(orderID: "cb-1", ordering: ordering, timeout: .milliseconds(100))))
        #expect(ContinuousClock.now - started < .seconds(10))
    }

    @Test("Reading an order back has a 15 s limit, and an authorized payment waits 60 s for Coinbase to commit it")
    func timeouts() {
        #expect(SessionCollectionTopUpper.orderLookupTimeout == .seconds(15))
        #expect(SessionCollectionTopUpper.authorizationTimeout == .seconds(60))
    }

    nonisolated private static func status(_ status: String) throws -> OnrampOrderStatusResponse {
        let json = #"{"order":{"status":"\#(status)"}}"#
        return try JSONDecoder().decode(OnrampOrderStatusResponse.self, from: Data(json.utf8))
    }
}
