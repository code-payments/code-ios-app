import Testing
import Foundation
@testable import FlipcashCore
import FlipcashAPI

@Suite("UserFlags.tipPresets")
struct UserFlagsTipPresetsTests {

    private func proto(
        _ rows: [(region: String, minimum: Double, low: Double, medium: Double, high: Double)]
    ) -> Flipcash_Account_V1_UserFlags {
        .with {
            $0.tipPresets = rows.map { row in
                .with {
                    $0.region = .with { $0.value = row.region }
                    $0.minimum = row.minimum
                    $0.low = row.low
                    $0.medium = row.medium
                    $0.high = row.high
                }
            }
        }
    }

    @Test("Populates rows from proto with Decimal amounts")
    func populatesFromProto() {
        let flags = UserFlags(proto([
            ("usd", 1, 5, 10, 20),
            ("cad", 2, 5, 10, 25),
        ]))

        #expect(flags.tipPresets.count == 2)
        #expect(flags.tipPresets[0].currency == .usd)
        #expect(flags.tipPresets[0].minimum == 1)
        #expect(flags.tipPresets[0].low == 5)
        #expect(flags.tipPresets[0].medium == 10)
        #expect(flags.tipPresets[0].high == 20)
        #expect(flags.tipPresets[1].currency == .cad)
    }

    @Test("Unknown region codes are dropped")
    func dropsUnknownRegions() {
        let flags = UserFlags(proto([
            ("usd", 1, 5, 10, 20),
            ("zzz", 1, 2, 3, 4),
        ]))

        #expect(flags.tipPresets.count == 1)
        #expect(flags.tipPresets[0].currency == .usd)
    }

    @Test("Lookup returns the row matching the currency")
    func lookupMatchesCurrency() {
        let flags = UserFlags(proto([
            ("usd", 1, 5, 10, 20),
            ("cad", 2, 5, 10, 25),
        ]))

        let presets = flags.tipPresets(for: .cad)

        #expect(presets?.currency == .cad)
        #expect(presets?.minimum == 2)
        #expect(presets?.high == 25)
    }

    @Test("Lookup falls back to the USD row for an unlisted currency")
    func lookupFallsBackToUSD() {
        let flags = UserFlags(proto([
            ("usd", 1, 5, 10, 20),
        ]))

        let presets = flags.tipPresets(for: .jpy)

        #expect(presets?.currency == .usd)
    }

    @Test("Lookup returns nil when no rows exist")
    func lookupNilWithoutRows() {
        let flags = UserFlags(proto([]))

        #expect(flags.tipPresets(for: .usd) == nil)
    }

    @Test("Minimum compares display-rounded values in the row's own currency")
    func minimumComparesDisplayRounded() {
        let presets = UserFlags.TipPresets(currency: .usd, minimum: 5, low: 5, medium: 10, high: 20)

        #expect(presets.meetsMinimum(usd(5)))
        #expect(!presets.meetsMinimum(usd(Decimal(string: "4.99")!)))
        // 4.996 displays as $5.00, and what we display is what we accept.
        #expect(presets.meetsMinimum(usd(Decimal(string: "4.996")!)))
        #expect(!presets.meetsMinimum(usd(Decimal(string: "4.994")!)))
    }

    @Test("A cross-currency amount falls back to its USD value against a USD row")
    func minimumFallsBackToUSDValue() {
        let presets = UserFlags.TipPresets(currency: .usd, minimum: 1, low: 5, medium: 10, high: 20)

        // 300 JPY at 150 JPY/USD is worth $2 — above the $1 floor.
        #expect(presets.meetsMinimum(jpy(300)))
        // 120 JPY is worth $0.80 — below it.
        #expect(!presets.meetsMinimum(jpy(120)))
    }

    private func usd(_ value: Decimal) -> ExchangedFiat {
        ExchangedFiat(
            nativeAmount: FiatAmount(value: value, currency: .usd),
            rate: Rate(fx: 1, currency: .usd)
        )
    }

    private func jpy(_ value: Decimal) -> ExchangedFiat {
        ExchangedFiat(
            nativeAmount: FiatAmount(value: value, currency: .jpy),
            rate: Rate(fx: 150, currency: .jpy)
        )
    }

    @Test("Fractional preset amounts survive the double decode exactly")
    func fractionalAmountsExact() {
        let flags = UserFlags(proto([
            ("usd", 0.5, 2.5, 12.5, 50.25),
        ]))

        let presets = flags.tipPresets(for: .usd)

        #expect(presets?.minimum == Decimal(string: "0.5"))
        #expect(presets?.low == Decimal(string: "2.5"))
        #expect(presets?.medium == Decimal(string: "12.5"))
        #expect(presets?.high == Decimal(string: "50.25"))
    }
}
