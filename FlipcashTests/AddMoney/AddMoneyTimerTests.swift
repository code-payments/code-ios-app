//
//  AddMoneyTimerTests.swift
//  FlipcashTests
//

import Foundation
import Testing
@testable import Flipcash
import FlipcashCore

@Suite("AddMoneyTimer")
struct AddMoneyTimerTests {

    private let clock = ManualInstantClock()
    private let timer: AddMoneyTimer

    init() {
        timer = AddMoneyTimer(now: clock.now)
    }

    /// Order at 100ms, payment +200, Coinbase +300, deposit +400, swap +500, credit +600, so total 2100.
    private func runFullPurchase() {
        timer.start()
        clock.advance(by: .milliseconds(100))
        timer.mark(.orderPlaced)
        clock.advance(by: .milliseconds(200))
        timer.mark(.paymentAuthorized)
        clock.advance(by: .milliseconds(300))
        timer.mark(.paymentCompleted)
        clock.advance(by: .milliseconds(400))
        timer.mark(.usdcSeen)
        clock.advance(by: .milliseconds(500))
        timer.mark(.swapped)
        clock.advance(by: .milliseconds(600))
        timer.mark(.credited)
    }

    @Test("Each phase is the gap between its two moments and the total runs from start")
    func fullPurchase() {
        runFullPurchase()

        #expect(timer.finish() == AddMoneyPhases(
            order: 100, payment: 200, coinbase: 300, deposit: 400, swap: 500, credit: 600, total: 2_100
        ))
    }

    @Test("A moment counts only the first time")
    func firstMarkOnly() {
        timer.start()
        timer.mark(.orderPlaced)
        clock.advance(by: .milliseconds(50))
        timer.mark(.orderPlaced)
        clock.advance(by: .milliseconds(50))
        timer.mark(.paymentAuthorized)

        let phases = timer.finish()
        #expect(phases?.order == 0)
        #expect(phases?.payment == 100)
    }

    @Test("Sweep moments before the payment completes are ignored")
    func sweepBeforePaymentCompleted() {
        timer.start()
        timer.mark(.orderPlaced)
        clock.advance(by: .milliseconds(100))
        timer.mark(.usdcSeen)
        timer.mark(.swapped)
        clock.advance(by: .milliseconds(100))
        timer.mark(.paymentCompleted)
        clock.advance(by: .milliseconds(100))
        timer.mark(.usdcSeen)

        let phases = timer.finish()
        #expect(phases?.deposit == 100)
        #expect(phases?.swap == nil)
    }

    @Test("A phase is nil when either moment is missing")
    func missingMoment() {
        timer.start()
        clock.advance(by: .milliseconds(10))
        timer.mark(.orderPlaced)
        clock.advance(by: .milliseconds(20))
        timer.mark(.paymentCompleted)

        #expect(timer.finish() == AddMoneyPhases(
            order: 10, payment: nil, coinbase: nil, deposit: nil, swap: nil, credit: nil, total: 30
        ))
    }

    @Test("Finishing closes the purchase")
    func finishCloses() {
        runFullPurchase()
        _ = timer.finish()

        timer.mark(.orderPlaced)
        #expect(timer.finish() == nil)
    }

    @Test("Marks before start are dropped, and a restart forgets the earlier purchase")
    func startResets() {
        timer.mark(.orderPlaced)
        timer.start()
        timer.mark(.orderPlaced)
        clock.advance(by: .milliseconds(40))
        timer.start()
        clock.advance(by: .milliseconds(5))

        #expect(timer.finish() == AddMoneyPhases(
            order: nil, payment: nil, coinbase: nil, deposit: nil, swap: nil, credit: nil, total: 5
        ))
    }

    @Test("Only a Coinbase send reads, and so closes, the purchase", arguments: [
        (DepositMethod.phantom, false),
        (.otherWallet, false),
        (.coinbase, true),
    ])
    func phasesByMethod(method: DepositMethod, carriesPhases: Bool) {
        timer.start()

        #expect((timer.finish(for: method) != nil) == carriesPhases)
        #expect((timer.finish() == nil) == carriesPhases)
    }
}

/// `Add Money` as sent for each outcome, with the wire names the catalogue spells.
@MainActor
@Suite("Add Money phase times", .serialized)
struct AddMoneyPhaseEventsTests {

    private let clock = ManualInstantClock()
    private let timer: AddMoneyTimer

    private static let tenDollars = ExchangedFiat(
        onChainAmount: TokenAmount(quarks: 10_000_000, mint: .usdf),
        nativeAmount: .usd(10),
        currencyRate: .oneToOne
    )

    private static let timeKeys = [
        "Order Time", "Payment Time", "Coinbase Time", "Deposit Time", "Swap Time", "Credit Time", "Total Time",
    ]

    init() {
        timer = AddMoneyTimer(now: clock.now)
    }

    private func timeProperties(of event: SentEvent) -> [String: Double] {
        Dictionary(uniqueKeysWithValues: Self.timeKeys.compactMap { key in
            (event.properties[key] as? Double).map { (key, $0) }
        })
    }

    private func makeViewModel(method: DepositMethod) -> AddMoneyProcessingViewModel {
        AddMoneyProcessingViewModel(
            input: AddMoneyProcessingInput(amount: Self.tenDollars, method: method, depositRef: nil),
            pollInterval: .milliseconds(1),
            timeout: .milliseconds(200)
        )
    }

    private func settlement() throws -> AddMoneyProcessingViewModelTests.FakeAddMoneySettling {
        let settlement = AddMoneyProcessingViewModelTests.FakeAddMoneySettling()
        settlement.risenBalance = try AddMoneyProcessingViewModelTests.usdfBalance(dollars: 10)
        settlement.risesAfterUpdates = 1
        return settlement
    }

    @Test("A Coinbase success sends all seven phase times")
    func coinbaseSuccess() async throws {
        timer.start()
        clock.advance(by: .milliseconds(100))
        timer.mark(.orderPlaced)
        clock.advance(by: .milliseconds(200))
        timer.mark(.paymentAuthorized)
        clock.advance(by: .milliseconds(300))
        timer.mark(.paymentCompleted)
        let viewModel = makeViewModel(method: .coinbase)
        let settlement = try settlement()

        let sent = await Analytics.recordingSendsAsync {
            await viewModel.run(settlement: settlement, timer: timer) { [clock, timer] in
                clock.advance(by: .milliseconds(400))
                timer.mark(.usdcSeen)
                clock.advance(by: .milliseconds(500))
                timer.mark(.swapped)
                clock.advance(by: .milliseconds(600))
                return true
            }
        }

        let event = try sent.single
        #expect(event.name == "Add Money")
        #expect(event.properties["Method"] as? String == "Coinbase")
        #expect(event.properties["State"] as? String == "Success")
        #expect(timeProperties(of: event) == [
            "Order Time": 100, "Payment Time": 200, "Coinbase Time": 300, "Deposit Time": 400,
            "Swap Time": 500, "Credit Time": 600, "Total Time": 2_100,
        ])
    }

    @Test("A Coinbase delivery timeout sends the finished phases and the total")
    func coinbaseDeliveryTimeout() async throws {
        timer.start()
        clock.advance(by: .milliseconds(100))
        timer.mark(.orderPlaced)
        clock.advance(by: .milliseconds(200))
        timer.mark(.paymentAuthorized)
        clock.advance(by: .milliseconds(300))
        timer.mark(.paymentCompleted)
        clock.advance(by: .milliseconds(400))
        let viewModel = makeViewModel(method: .coinbase)

        let sent = await Analytics.recordingSendsAsync {
            await viewModel.run(
                settlement: AddMoneyProcessingViewModelTests.FakeAddMoneySettling(),
                timer: timer
            ) { true }
        }

        let event = try sent.single
        #expect(event.properties["State"] as? String == "Failure")
        #expect(timeProperties(of: event) == [
            "Order Time": 100, "Payment Time": 200, "Coinbase Time": 300, "Total Time": 1_000,
        ])
    }

    @Test("A Coinbase failure before the order is placed sends the total alone")
    func coinbaseFailureBeforeOrder() throws {
        timer.start()
        clock.advance(by: .milliseconds(250))

        let sent = Analytics.recordingSends {
            Analytics.addMoney(
                method: .coinbase,
                exchangedFiat: Self.tenDollars,
                successful: false,
                error: NSError(domain: "D", code: 1),
                phases: timer.finish(for: .coinbase)
            )
        }

        #expect(try timeProperties(of: sent.single) == ["Total Time": 250])
    }

    @Test("A Phantom send carries no Time properties and leaves the timer open", arguments: [true, false])
    func phantomSendsNoTimes(success: Bool) async throws {
        timer.start()
        let viewModel = makeViewModel(method: .phantom)
        let settlement = success ? try settlement() : AddMoneyProcessingViewModelTests.FakeAddMoneySettling()

        let sent = await Analytics.recordingSendsAsync {
            await viewModel.run(settlement: settlement, timer: timer) { true }
        }

        let event = try sent.single
        #expect(event.properties["Method"] as? String == "Phantom")
        #expect(timeProperties(of: event).isEmpty)
        #expect(timer.finish() != nil)
    }
}
