//
//  CurrencyPaymentSelectionViewModelTests.swift
//  FlipcashTests
//

import Foundation
import Testing
@testable import FlipcashCore
@testable import Flipcash

@Suite("CurrencyPaymentSelectionViewModel")
@MainActor
struct CurrencyPaymentSelectionViewModelTests {

    private static let jeffySupply: UInt64 = 50_000 * 10_000_000_000

    /// $20 launch cost — the default new-currency total.
    private static let launchCost = TokenAmount(quarks: 20_000_000, mint: .usdf)

    private static func makeContainer(
        holdings: [SessionContainer.Holding],
        currency: CurrencyCode = .usd,
        fx: Double = 1.0
    ) throws -> SessionContainer {
        let container = try SessionContainer.makeTest(holdings: holdings)
        container.ratesController.configureTestRates(
            balanceCurrency: currency,
            rates: [Rate(fx: Decimal(fx), currency: currency)]
        )
        return container
    }

    private static func makeViewModel(container: SessionContainer, displayRate: Rate? = nil) -> CurrencyPaymentSelectionViewModel {
        CurrencyPaymentSelectionViewModel(
            launchCost: launchCost,
            displayRate: displayRate,
            session: container.session,
            ratesController: container.ratesController
        )
    }

    @Test("Zero-value balances are hidden from the list")
    func hidesZeroBalances() throws {
        let container = try Self.makeContainer(holdings: [
            .init(mint: .usdf, quarks: 30_000_000),
            .init(mint: .makeLaunchpad(address: .jeffy, supplyFromBonding: Self.jeffySupply), quarks: 0),
        ])
        let viewModel = Self.makeViewModel(container: container)

        #expect(viewModel.rows.contains { $0.stored.mint == .usdf })
        #expect(!viewModel.rows.contains { $0.stored.mint == .jeffy })
    }

    @Test("Row eligibility tracks the launch cost", arguments: [
        (quarks: UInt64(5_000_000), eligible: false),  // $5 — below $20
        (quarks: UInt64(30_000_000), eligible: true),  // $30 — covers $20
    ])
    func eligibilityTracksCost(quarks: UInt64, eligible: Bool) throws {
        let container = try Self.makeContainer(holdings: [.init(mint: .usdf, quarks: quarks)])
        let viewModel = Self.makeViewModel(container: container)
        let usdf = try #require(viewModel.rows.first { $0.stored.mint == .usdf })

        #expect(viewModel.isEligible(usdf) == eligible)
    }

    @Test("A fixed display rate overrides the user's balance currency")
    func fixedDisplayRateOverridesBalanceCurrency() throws {
        let container = try Self.makeContainer(
            holdings: [.init(mint: .usdf, quarks: 30_000_000)],
            currency: .cad,
            fx: 1.37
        )
        let viewModel = Self.makeViewModel(container: container, displayRate: .oneToOne)
        let usdf = try #require(viewModel.rows.first { $0.stored.mint == .usdf })

        #expect(usdf.exchangedFiat.nativeAmount.currency == .usd)
        #expect(usdf.exchangedFiat.nativeAmount.value == 30)
    }

    @Test("Selecting an eligible row raises the Ready To Create dialog")
    func eligibleSelectionRaisesDialog() throws {
        let container = try Self.makeContainer(holdings: [.init(mint: .usdf, quarks: 30_000_000)])
        let viewModel = Self.makeViewModel(container: container)
        let usdf = try #require(viewModel.rows.first { $0.stored.mint == .usdf })

        var confirmed: StoredBalance?
        viewModel.select(usdf) { confirmed = $0 }

        #expect(viewModel.dialogItem != nil)
        #expect(confirmed == nil) // fires only on the dialog's confirm action
    }
}
