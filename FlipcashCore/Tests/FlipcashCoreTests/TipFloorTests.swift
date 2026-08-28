import Testing
import Foundation
@testable import FlipcashCore

@Suite("TipFloor")
struct TipFloorTests {

    private let presets = UserFlags.TipPresets(currency: .usd, minimum: 1, low: 5, medium: 10, high: 20)

    /// CAD at 2 CAD/USD, EUR at 2 EUR/USD — so CAD 10 is USD 5 is EUR 10.
    private let rates: [CurrencyCode: Rate] = [
        .usd: Rate(fx: 1, currency: .usd),
        .cad: Rate(fx: 2, currency: .cad),
        .eur: Rate(fx: 2, currency: .eur),
    ]

    // MARK: - Resolution -

    @Test("The recipient's own fee is the floor, not the regional preset")
    func recipientFeeWins() {
        let floor = TipFloor.toOpenDM(
            recipientFee: FiatAmount(value: 25, currency: .usd),
            presets: presets,
            in: .usd,
            rates: rates
        )

        #expect(floor == .recipientFee(FiatAmount(value: 25, currency: .usd)))
    }

    @Test("The fee is restated in the currency the amount is entered in")
    func convertsFeeIntoEntryCurrency() {
        let floor = TipFloor.toOpenDM(
            recipientFee: FiatAmount(value: 10, currency: .cad),
            presets: presets,
            in: .eur,
            rates: rates
        )

        #expect(floor == .recipientFee(FiatAmount(value: 10, currency: .eur)))
    }

    @Test("Falls back to the preset when the recipient charges nothing")
    func fallsBackWhenNoFee() {
        let floor = TipFloor.toOpenDM(recipientFee: nil, presets: presets, in: .usd, rates: rates)

        #expect(floor == .preset(presets))
    }

    @Test("Falls back to the preset rather than state a floor in another currency")
    func fallsBackWhenRateMissing() {
        let floor = TipFloor.toOpenDM(
            recipientFee: FiatAmount(value: 10, currency: .cad),
            presets: presets,
            in: .jpy,
            rates: rates // no JPY leg
        )

        #expect(floor == .preset(presets))
    }

    @Test("A zero fee is no fee")
    func zeroFeeFallsBack() {
        let floor = TipFloor.toOpenDM(
            recipientFee: FiatAmount(value: 0, currency: .usd),
            presets: presets,
            in: .usd,
            rates: rates
        )

        #expect(floor == .preset(presets))
    }

    @Test("No fee and no presets leaves no floor")
    func nilWithoutEither() {
        #expect(TipFloor.toOpenDM(recipientFee: nil, presets: nil, in: .usd, rates: rates) == nil)
        #expect(TipFloor.systemMinimum(presets: nil) == nil)
    }

    // MARK: - Enforcement -

    @Test("A fee floor compares display-rounded values in its own currency")
    func feeComparesDisplayRounded() {
        let floor = TipFloor.recipientFee(FiatAmount(value: 5, currency: .usd))

        #expect(floor.isMet(by: usd(5)))
        #expect(!floor.isMet(by: usd(Decimal(string: "4.99")!)))
        // 4.996 displays as $5.00, and what we display is what we accept.
        #expect(floor.isMet(by: usd(Decimal(string: "4.996")!)))
    }

    @Test("A fee floor in another currency defers to the server rather than trap")
    func feeInAnotherCurrencyPasses() {
        let floor = TipFloor.recipientFee(FiatAmount(value: 5, currency: .eur))

        #expect(floor.isMet(by: usd(1)))
    }

    @Test("A preset floor enforces the preset row")
    func presetEnforcesRow() {
        let floor = TipFloor.preset(presets)

        #expect(floor.isMet(by: usd(1)))
        #expect(!floor.isMet(by: usd(Decimal(string: "0.99")!)))
        #expect(floor.displayed == FiatAmount(value: 1, currency: .usd))
    }

    private func usd(_ value: Decimal) -> ExchangedFiat {
        ExchangedFiat(
            nativeAmount: FiatAmount(value: value, currency: .usd),
            rate: Rate(fx: 1, currency: .usd)
        )
    }
}

@Suite("FiatAmount.converted")
struct FiatAmountConversionTests {

    private let rates: [CurrencyCode: Rate] = [
        .usd: Rate(fx: 1, currency: .usd),
        .cad: Rate(fx: 2, currency: .cad),
        .eur: Rate(fx: 2, currency: .eur),
    ]

    @Test("Same currency is returned untouched")
    func sameCurrency() {
        let amount = FiatAmount(value: Decimal(string: "10.005")!, currency: .cad)

        #expect(amount.converted(to: .cad, rates: rates) == amount)
    }

    @Test("Routes through USD and rounds to the target's precision")
    func routesThroughUSD() {
        let cad = FiatAmount(value: 10, currency: .cad)

        #expect(cad.converted(to: .usd, rates: rates) == FiatAmount(value: 5, currency: .usd))
        #expect(cad.converted(to: .eur, rates: rates) == FiatAmount(value: 10, currency: .eur))
    }

    @Test("Rounds to a zero-decimal currency's precision")
    func roundsToZeroDecimalCurrency() {
        let usd = FiatAmount(value: 1, currency: .usd)
        let rates = rates.merging([.jpy: Rate(fx: Decimal(string: "150.4")!, currency: .jpy)]) { _, new in new }

        #expect(usd.converted(to: .jpy, rates: rates) == FiatAmount(value: 150, currency: .jpy))
    }

    @Test("Nil when either leg has no rate")
    func nilWithoutRate() {
        #expect(FiatAmount(value: 10, currency: .cad).converted(to: .jpy, rates: rates) == nil)
        #expect(FiatAmount(value: 10, currency: .jpy).converted(to: .usd, rates: rates) == nil)
    }
}
