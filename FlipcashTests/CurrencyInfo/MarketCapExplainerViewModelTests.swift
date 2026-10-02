//
//  MarketCapExplainerViewModelTests.swift
//  FlipcashTests
//

import Foundation
import Testing
import FlipcashCore
import FlipcashStore
@testable import Flipcash

@MainActor
@Suite("MarketCapExplainerViewModel")
struct MarketCapExplainerViewModelTests {

    private static let supply: UInt64 = 50_000 * 10_000_000_000
    private static let heldQuarks: UInt64 = 2_000 * 10_000_000_000
    private static let mint = PublicKey.jeffy

    /// The USDF the curve pays for `heldQuarks` at `supply`, which is what the
    /// session's balance will carry as its value.
    private static func heldValue() throws -> Double {
        let stored = try StoredBalance(
            quarks: heldQuarks, symbol: "TEST", name: "Test Token",
            supplyFromBonding: supply, sellFeeBps: 0, mint: mint,
            vmAuthority: nil, updatedAt: .now, imageURL: nil, costBasis: 0
        )
        return NSDecimalNumber(decimal: stored.usdf.value).doubleValue
    }

    private func makeViewModel(
        metadata: MintMetadata = .makeLaunchpad(address: mint, supplyFromBonding: supply),
        heldQuarks: UInt64? = heldQuarks,
        costBasis: Double = 0,
        balanceCurrency: CurrencyCode = .usd,
        rates: [Rate] = []
    ) throws -> MarketCapExplainerViewModel {
        let database = Database.mock
        try database.insert(mints: [metadata], date: .now)
        if let heldQuarks {
            try database.insertBalance(quarks: heldQuarks, mint: Self.mint, costBasis: costBasis, date: .now)
        }
        let ratesController = RatesController(container: .mock, database: database)
        ratesController.configureTestRates(balanceCurrency: balanceCurrency, rates: rates)
        let session = Session.makeMock(database: database, ratesController: ratesController)
        return MarketCapExplainerViewModel(mint: Self.mint, session: session, ratesController: ratesController)
    }

    private func loadedViewModel(
        heldQuarks: UInt64? = heldQuarks,
        costBasis: Double = 0,
        balanceCurrency: CurrencyCode = .usd,
        rates: [Rate] = []
    ) async throws -> MarketCapExplainerViewModel {
        let viewModel = try makeViewModel(
            heldQuarks: heldQuarks, costBasis: costBasis,
            balanceCurrency: balanceCurrency, rates: rates
        )
        await viewModel.load()
        return viewModel
    }

    // MARK: - Loading

    @Test("Before load there is no explainer and no selection")
    func beforeLoad() throws {
        let viewModel = try makeViewModel()
        #expect(viewModel.explainer == nil)
        #expect(viewModel.selection == nil)
        #expect(viewModel.name == "")
    }

    @Test("A mint with no bonding-curve supply is unavailable")
    func noSupplyIsUnavailable() async throws {
        let viewModel = try makeViewModel(metadata: .makeBasic(address: Self.mint))
        await viewModel.load()
        #expect(viewModel.explainer == nil)
        guard case .unavailable = viewModel.loadingState else {
            Issue.record("expected .unavailable, got \(viewModel.loadingState)")
            return
        }
    }

    // MARK: - Today

    @Test("After load the selection is Today and the slider sits on Today")
    func loadSelectsToday() async throws {
        let viewModel = try await loadedViewModel()
        let explainer = try #require(viewModel.explainer)

        #expect(viewModel.name == "Test Token")
        #expect(viewModel.selection == explainer.todayStop)
        #expect(viewModel.selection?.isToday == true)
        #expect(viewModel.trackPosition == explainer.trackPosition(of: explainer.todayStop))
    }

    @Test("Moving the slider moves the selection; releasing to Today's position returns it to Today")
    func resetToToday() async throws {
        let viewModel = try await loadedViewModel()
        let explainer = try #require(viewModel.explainer)
        let todayPosition = explainer.trackPosition(of: explainer.todayStop)

        viewModel.trackPosition = 0.95
        #expect(viewModel.selection?.isToday == false)
        #expect(viewModel.selection == explainer.stop(atTrackPosition: 0.95))

        viewModel.trackPosition = todayPosition
        #expect(viewModel.selection == explainer.todayStop)
    }

    // MARK: - Display currency

    @Test("USD display leaves values in dollars")
    func usdDisplay() async throws {
        let viewModel = try await loadedViewModel()
        #expect(viewModel.reserveText(5_000) == "$5K")
        #expect(viewModel.reserveText(10_000_000) == "$10M")
        #expect(viewModel.priceText(Decimal(string: "0.02994")!) == "$0.02994")
        #expect(viewModel.priceText(Decimal(string: "0.887")!) == "$0.887")
        #expect(viewModel.priceText(8.78) == "$8.78")
    }

    @Test("Reserve, price and worth convert to the balance currency; the curve math stays USD")
    func convertsToBalanceCurrency() async throws {
        let rate = Rate(fx: 2, currency: .cad)
        let viewModel = try await loadedViewModel(balanceCurrency: .cad, rates: [rate])
        let explainer = try #require(viewModel.explainer)
        let today = explainer.todayStop

        #expect(viewModel.reserveText(5_000) == FiatAmount(value: 10_000, currency: .cad).formattedAbbreviated())
        #expect(viewModel.reserveText(5_000) != FiatAmount.usd(5_000).formattedAbbreviated())

        let worthUSD = try #require(explainer.worth(at: today))
        #expect(viewModel.worthText(at: today) == FiatAmount(value: worthUSD * 2, currency: .cad).formatted())

        // Price 0.8 USD -> 1.6 CAD, four fractional digits max for a sub-$1 price.
        let priceText = viewModel.priceText(Decimal(string: "0.8")!)
        #expect(priceText == NumberFormatter.fiat(currency: .cad, minimumFractionDigits: 2, maximumFractionDigits: 4)
            .string(from: NSDecimalNumber(string: "1.6")))

        // The explainer itself never converts.
        #expect(viewModel.selection == today)
        #expect(explainer.todayStop.reserve == today.reserve)
    }

    @Test("Without a cached rate the balance currency falls back to one-to-one")
    func missingRateIsOneToOne() async throws {
        let viewModel = try await loadedViewModel(balanceCurrency: .cad, rates: [])
        #expect(viewModel.reserveText(5_000) == FiatAmount.usd(5_000).formattedAbbreviated())
    }

    @Test("Worth is a dash when holdings are unknown")
    func worthWithoutHoldings() async throws {
        let viewModel = try await loadedViewModel(heldQuarks: nil)
        let today = try #require(viewModel.explainer?.todayStop)
        #expect(viewModel.worthText(at: today) == "–")
    }

    // MARK: - Appreciation

    @Test("A balance worth more than its cost basis is a positive appreciation")
    func appreciationPositive() async throws {
        let viewModel = try await loadedViewModel(costBasis: try Self.heldValue() - 5)
        #expect(viewModel.appreciationSign == .positive)
        #expect(viewModel.appreciationText == "+$5.00")
    }

    @Test("A balance worth less than its cost basis is a negative appreciation")
    func appreciationNegative() async throws {
        let viewModel = try await loadedViewModel(costBasis: try Self.heldValue() + 5)
        #expect(viewModel.appreciationSign == .negative)
        #expect(viewModel.appreciationText == "-$5.00")
    }

    @Test("A balance exactly at its cost basis is zero, rendered as a gain")
    func appreciationZero() async throws {
        let viewModel = try await loadedViewModel(costBasis: try Self.heldValue())
        #expect(viewModel.appreciationSign == .zero)
        #expect(viewModel.appreciationText == "+$0.00")
    }

    @Test("A sub-cent loss is zero, never a '-$0.00'")
    func appreciationSubCentLoss() async throws {
        let viewModel = try await loadedViewModel(costBasis: try Self.heldValue() + 0.001)
        #expect(viewModel.appreciationSign == .zero)
        #expect(viewModel.appreciationText == "+$0.00")
    }

    @Test("With no balance the appreciation is a dash and zero")
    func appreciationUnknownBalance() async throws {
        let viewModel = try await loadedViewModel(heldQuarks: nil)
        #expect(viewModel.appreciationSign == .zero)
        #expect(viewModel.appreciationText == "–")
    }

    @Test("A balance with no recorded cost basis counts its whole value as gain")
    func appreciationUnknownCostBasis() async throws {
        let viewModel = try await loadedViewModel(costBasis: 0)
        #expect(viewModel.appreciationSign == .positive)
        #expect(viewModel.appreciationText.hasPrefix("+"))
    }

    @Test("Appreciation text converts to the balance currency")
    func appreciationConverts() async throws {
        let rate = Rate(fx: 2, currency: .cad)
        let viewModel = try await loadedViewModel(
            costBasis: try Self.heldValue() - 5, balanceCurrency: .cad, rates: [rate]
        )
        #expect(viewModel.appreciationText == "+" + FiatAmount(value: 10, currency: .cad).formatted())
    }

    // MARK: - Share of supply

    @Test("A missing fraction is a dash")
    func percentNil() throws {
        #expect(try makeViewModel().percentText(nil) == "–")
    }

    @Test("Exact zero reads 0%, not '<0.01%'")
    func percentExactZero() throws {
        #expect(try makeViewModel().percentText(0) == "0%")
    }

    @Test("A non-zero share under 0.01% reads '<0.01%'", arguments: ["0.00001", "0.00005", "0.00009999"])
    func percentTiny(fraction: String) throws {
        #expect(try makeViewModel().percentText(Decimal(string: fraction)!) == "<0.01%")
    }

    @Test("At and above 0.01% the percent is shown, up to two decimals")
    func percentShown() throws {
        let viewModel = try makeViewModel()
        #expect(viewModel.percentText(Decimal(string: "0.0001")!) == "0.01%")
        #expect(viewModel.percentText(Decimal(string: "0.0123")!) == "1.23%")
        #expect(viewModel.percentText(Decimal(string: "0.5")!) == "50%")
    }

    @Test("Tokens format as whole numbers, a dash when unknown")
    func tokens() throws {
        let viewModel = try makeViewModel()
        #expect(viewModel.tokensText(nil) == "–")
        #expect(viewModel.tokensText(12_400) == "12,400")
        #expect(viewModel.tokensText(Decimal(string: "12400.6")!) == "12,401")
    }
}
