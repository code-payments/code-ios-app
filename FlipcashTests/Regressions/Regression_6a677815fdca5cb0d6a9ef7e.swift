//
//  Regression_6a677815fdca5cb0d6a9ef7e.swift
//  FlipcashTests
//
//  Server denial: "tip amount is below the recipient's chat initialization
//  fee". The Start Chatting sheet submits the floor `TipFloor.toOpenDM` states,
//  which is the recipient's fee converted into the entry currency. The
//  conversion rounded half-up, so it could land under the fee — 600 INR at
//  95.95 INR/USD is $6.2533, stated as $6.25, which is 599.69 INR. `isMet`
//  judged the entry against that same figure, so it passed locally and the
//  server denied it.
//
//  Fix: `toOpenDM` rounds the converted fee up, so the stated floor always
//  covers the fee at the rate it was converted with.
//

import Foundation
import Testing
@testable import FlipcashCore

@Suite("Regression: 6a67781 – converted DM fee floor rounds below the fee", .bug("6a677815fdca5cb0d6a9ef7e"))
struct Regression_6a67781 {

    private let usdRate = Rate(fx: 1, currency: .usd)
    private let inrRate = Rate(fx: Decimal(string: "95.95")!, currency: .inr)
    private let ngnRate = Rate(fx: 1326, currency: .ngn)

    private var rates: [CurrencyCode: Rate] {
        [.usd: usdRate, .inr: inrRate, .ngn: ngnRate]
    }

    private func floor(for fee: FiatAmount) -> TipFloor? {
        TipFloor.toOpenDM(recipientFee: fee, presets: nil, in: .usd, rates: rates)
    }

    @Test("A 600 INR fee is stated as $6.26, which covers it, not $6.25")
    func inrFee_floorCoversFee() throws {
        let floor = try #require(floor(for: FiatAmount(value: 600, currency: .inr)))

        #expect(floor.displayed == .usd(Decimal(string: "6.26")!))
        #expect(floor.displayed.converting(to: inrRate).value >= 600)
    }

    @Test("The $6.25 the sheet used to submit no longer clears the floor locally")
    func inrFee_roundedDownEntryIsRejected() throws {
        let floor = try #require(floor(for: FiatAmount(value: 600, currency: .inr)))
        let entered = ExchangedFiat(nativeAmount: .usd(Decimal(string: "6.25")!), rate: usdRate)

        #expect(!floor.isMet(by: entered))
    }

    @Test("A 1500 NGN fee is stated as $1.14, which covers it, not $1.13")
    func ngnFee_floorCoversFee() throws {
        let floor = try #require(floor(for: FiatAmount(value: 1500, currency: .ngn)))

        #expect(floor.displayed == .usd(Decimal(string: "1.14")!))
        #expect(floor.displayed.converting(to: ngnRate).value >= 1500)
    }

    @Test("A fee that converts exactly is not bumped a cent")
    func exactConversion_isUnchanged() throws {
        let exactRates: [CurrencyCode: Rate] = [.usd: usdRate, .inr: Rate(fx: 100, currency: .inr)]
        let floor = try #require(TipFloor.toOpenDM(
            recipientFee: FiatAmount(value: 600, currency: .inr),
            presets: nil,
            in: .usd,
            rates: exactRates
        ))

        #expect(floor.displayed == .usd(6))
    }
}
