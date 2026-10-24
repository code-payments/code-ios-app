import Foundation
import Testing
@testable import FlipcashCore

/// `test-vectors/viewer_amount.json`: a fiat amount restated in the display currency. The canonical
/// copy lives in the orchestrator repo; this one is synced. Never edit it locally.
@Suite struct ViewerAmountVectorTests {

    struct Fixture: Decodable, Sendable {
        let minorDigits: [String: Int]
        let cases: [Case]
    }

    struct Money: Decodable, Sendable {
        let amount: String
        let currency: String
    }

    struct Case: Decodable, Sendable, CustomTestStringConvertible {
        struct Expected: Decodable, Sendable {
            let converted: Bool
            let viewer: Money
        }

        let name: String
        let native: Money
        let mint: String
        let settledUsd: String?
        let display: String
        let rates: [String: String]
        let expected: Expected

        var testDescription: String { name }
    }

    static let fixture: Fixture = {
        let url = Bundle.module.url(forResource: "viewer_amount", withExtension: "json", subdirectory: "Fixtures")!
        return try! JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }()

    /// Any mint that is not USDF takes the today's-rates path.
    static let otherMint = try! PublicKey(base58: "So11111111111111111111111111111111111111112")

    @Test("forViewer matches every case", arguments: fixture.cases)
    func forViewer(_ vector: Case) {
        let native = Self.amount(vector.native)
        let rates = Self.rates(vector.rates)
        let fiat: ExchangedFiat
        switch vector.mint {
        case "usdf":
            fiat = ExchangedFiat(
                onChainAmount: TokenAmount(wholeTokens: Decimal(string: vector.settledUsd!)!, mint: .usdf),
                nativeAmount: native,
                currencyRate: Rate(fx: 1, currency: native.currency)
            )
        default:
            fiat = ExchangedFiat(
                onChainAmount: TokenAmount(wholeTokens: native.value, mint: Self.otherMint),
                nativeAmount: native,
                currencyRate: Rate(fx: 1, currency: native.currency)
            )
        }

        let shown = fiat.forViewer(in: Self.currency(vector.display), rates: rates)

        Self.assert(shown, matches: vector)
    }

    @Test("converted(to:rates:) matches every plain case", arguments: fixture.cases.filter { $0.mint == "other" })
    func converted(_ vector: Case) {
        let native = Self.amount(vector.native)
        let shown = native.converted(to: Self.currency(vector.display), rates: Self.rates(vector.rates)) ?? native

        Self.assert(shown, matches: vector)
    }

    // MARK: - Helpers -

    private static func assert(_ shown: FiatAmount, matches vector: Case) {
        let expected = amount(vector.expected.viewer)
        let digits = fixture.minorDigits[vector.expected.viewer.currency]!
        #expect(shown.currency == expected.currency)
        #expect(shown.value.roundedHalfEven(to: digits) == expected.value)
        #expect((shown.currency != currency(vector.native.currency)) == vector.expected.converted)
    }

    private static func currency(_ code: String) -> CurrencyCode {
        CurrencyCode(rawValue: code.lowercased())!
    }

    private static func amount(_ money: Money) -> FiatAmount {
        FiatAmount(value: Decimal(string: money.amount)!, currency: currency(money.currency))
    }

    private static func rates(_ table: [String: String]) -> [CurrencyCode: Rate] {
        Dictionary(uniqueKeysWithValues: table.map { code, fx in
            let currency = currency(code)
            return (currency, Rate(fx: Decimal(string: fx)!, currency: currency))
        })
    }
}
