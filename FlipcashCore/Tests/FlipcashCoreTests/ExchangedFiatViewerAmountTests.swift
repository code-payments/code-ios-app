//
//  ExchangedFiatViewerAmountTests.swift
//  FlipcashCore
//

import Foundation
import Testing
import FlipcashCore

/// Every amount is shown in the viewer's own currency, so a tip denominated in
/// someone else's has to be restated — and the restated figure has to hold still,
/// which is why a USDF payment converts from the USD value it settled at rather
/// than from today's peso.
@Suite("ExchangedFiat Viewer Amount Tests")
struct ExchangedFiatViewerAmountTests {

    /// A mint that isn't USDF, so it takes the no-anchor path.
    private let bondedMint = try! PublicKey(base58: "So11111111111111111111111111111111111111112")

    private let eurRate = Rate(fx: 0.9, currency: .eur)

    private func usd(_ value: Decimal) -> FiatAmount { FiatAmount(value: value, currency: .usd) }
    private func ars(_ value: Decimal) -> FiatAmount { FiatAmount(value: value, currency: .ars) }
    private func eur(_ value: Decimal) -> FiatAmount { FiatAmount(value: value, currency: .eur) }

    /// A USDF payment as the feed carries it: the settled dollars on-chain, the
    /// amount the payer entered, and the FX it settled at.
    private func usdfPayment(dollars: Decimal, native: FiatAmount, fx: Decimal) -> ExchangedFiat {
        ExchangedFiat(
            onChainAmount: TokenAmount(wholeTokens: dollars, mint: .usdf),
            nativeAmount: native,
            currencyRate: Rate(fx: fx, currency: native.currency)
        )
    }

    /// A bonded-mint payment. Its rate is the per-token one the feed synthesizes
    /// from `nativeAmount / onChainAmount`, which is why the on-chain side is no
    /// USD anchor.
    private func bondedPayment(tokens: Decimal, native: FiatAmount) -> ExchangedFiat {
        ExchangedFiat(
            onChainAmount: TokenAmount(wholeTokens: tokens, mint: bondedMint),
            nativeAmount: native,
            currencyRate: Rate(fx: native.value / tokens, currency: native.currency)
        )
    }

    @Test("An amount already in the viewer's currency is shown as it moved")
    func sameCurrency() {
        let amount = usdfPayment(dollars: 5, native: usd(5), fx: 1)

        #expect(amount.forViewer(in: .usd, rates: [:]) == usd(5))
    }

    @Test("A USDF tip in pesos shows the dollars it settled at")
    func usdfLeadsWithSettledDollars() {
        let amount = usdfPayment(dollars: 5, native: ars(7_500), fx: 1_500)

        // Today's peso has moved; the settled dollars have not.
        let shown = amount.forViewer(in: .usd, rates: [.ars: Rate(fx: 3_000, currency: .ars)])

        #expect(shown == usd(5))
    }

    @Test("A USDF tip crosses its settled dollars into whatever currency the viewer reads")
    func usdfCrossesIntoViewerCurrency() {
        let amount = usdfPayment(dollars: 5, native: ars(7_500), fx: 1_500)

        #expect(amount.forViewer(in: .eur, rates: [.eur: eurRate]) == eur(4.5))
    }

    @Test("A non-USDF tip has no settled dollars, so it crosses through today's rates")
    func bondedCrossesThroughRates() {
        let amount = bondedPayment(tokens: 40, native: ars(7_500))

        let shown = amount.forViewer(in: .usd, rates: [.ars: Rate(fx: 1_500, currency: .ars)])

        #expect(shown == usd(5))
    }

    @Test("A non-USDF tip with no rate to cross is shown as it moved")
    func bondedWithoutRateFallsBack() {
        let amount = bondedPayment(tokens: 40, native: ars(7_500))

        #expect(amount.forViewer(in: .usd, rates: [:]) == ars(7_500))
    }

    @Test("An unusable rate is treated as no rate at all")
    func zeroRateFallsBack() {
        let amount = bondedPayment(tokens: 40, native: ars(7_500))

        #expect(amount.forViewer(in: .usd, rates: [.ars: Rate(fx: 0, currency: .ars)]) == ars(7_500))
    }

    @Test("A display currency with no rate converts nothing")
    func missingDisplayRateFallsBack() {
        let amount = usdfPayment(dollars: 5, native: ars(7_500), fx: 1_500)

        #expect(amount.forViewer(in: .eur, rates: [:]) == ars(7_500))
        #expect(amount.forViewer(in: .eur, rates: [.eur: Rate(fx: 0, currency: .eur)]) == ars(7_500))
    }

    @Test("An amount that signs itself is not signed twice")
    func testAmountIsNotSignedTwice() {
        // The row supplies the sign because feed amounts are magnitudes; one that
        // isn't would otherwise format as "--$5.00".
        #expect(usd(-5).formatted(signPrefix: "-") == usd(-5).formatted())
        #expect(usd(5).formatted(signPrefix: "-") == "-" + usd(5).formatted())
        #expect(usd(5).formatted(signPrefix: nil) == usd(5).formatted())
    }
}
