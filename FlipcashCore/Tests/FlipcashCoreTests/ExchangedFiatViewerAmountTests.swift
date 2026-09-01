//
//  ExchangedFiatViewerAmountTests.swift
//  FlipcashCore
//

import Foundation
import Testing
import FlipcashCore

/// An activity row leads with the viewer's own currency, so a tip denominated in
/// someone else's has to be restated — and the restated figure has to hold still,
/// which is why a USDF payment converts from the USD value it settled at rather
/// than from today's peso.
@Suite("ExchangedFiat Viewer Amount Tests")
struct ExchangedFiatViewerAmountTests {

    /// A mint that isn't USDF, so it takes the no-anchor path.
    private let bondedMint = try! PublicKey(base58: "So11111111111111111111111111111111111111112")

    private let usdRate = Rate(fx: 1, currency: .usd)
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

    @Test("An amount already in the viewer's currency shows one line")
    func testSameCurrencyShowsOneLine() {
        let amount = usdfPayment(dollars: 5, native: usd(5), fx: 1)

        let shown = amount.forViewer(preferredRate: usdRate, rates: [:])

        #expect(shown.viewer == usd(5))
        #expect(shown.transferred == nil)
    }

    @Test("A USDF tip in pesos leads with the dollars it settled at")
    func testUSDFTipUsesSettledDollars() {
        let amount = usdfPayment(dollars: 5, native: ars(7_500), fx: 1_500)

        // The peso has halved against the dollar since — the row still reads $5,
        // not $2.50.
        let shown = amount.forViewer(
            preferredRate: usdRate,
            rates: [.ars: Rate(fx: 3_000, currency: .ars)]
        )

        #expect(shown.viewer == usd(5))
        #expect(shown.transferred == ars(7_500))
    }

    @Test("A USDF tip crosses its settled dollars into whatever currency the viewer reads")
    func testUSDFTipCrossesIntoViewerCurrency() {
        let amount = usdfPayment(dollars: 5, native: ars(7_500), fx: 1_500)

        let shown = amount.forViewer(preferredRate: eurRate, rates: [:])

        #expect(shown.viewer == eur(4.5))
        #expect(shown.transferred == ars(7_500))
    }

    @Test("A non-USDF tip has no settled dollars, so it crosses through today's rates")
    func testBondedTipCrossesThroughCurrentRates() {
        let amount = bondedPayment(tokens: 1_234, native: ars(7_500))

        // `onChainAmount` holds the mint's own tokens here, not dollars, so it is
        // ignored.
        let shown = amount.forViewer(
            preferredRate: usdRate,
            rates: [.ars: Rate(fx: 1_500, currency: .ars)]
        )

        #expect(shown.viewer == usd(5))
        #expect(shown.transferred == ars(7_500))
    }

    @Test("A non-USDF tip with no rate to cross falls back to what was transferred")
    func testBondedTipWithoutRateFallsBack() {
        let amount = bondedPayment(tokens: 1_234, native: ars(7_500))

        let shown = amount.forViewer(preferredRate: usdRate, rates: [:])

        #expect(shown.viewer == ars(7_500))
        #expect(shown.transferred == nil)
    }

    @Test("An unusable rate is treated as no rate at all")
    func testZeroRateIsTreatedAsMissing() {
        let amount = bondedPayment(tokens: 1_234, native: ars(7_500))

        let shown = amount.forViewer(
            preferredRate: usdRate,
            rates: [.ars: Rate(fx: 0, currency: .ars)]
        )

        #expect(shown.viewer == ars(7_500))
        #expect(shown.transferred == nil)
    }

    @Test("An unusable viewer rate leaves the transferred amount alone")
    func testZeroViewerRateFallsBack() {
        let amount = usdfPayment(dollars: 5, native: ars(7_500), fx: 1_500)

        let shown = amount.forViewer(
            preferredRate: Rate(fx: 0, currency: .eur),
            rates: [.ars: Rate(fx: 1_500, currency: .ars)]
        )

        #expect(shown.viewer == ars(7_500))
        #expect(shown.transferred == nil)
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
