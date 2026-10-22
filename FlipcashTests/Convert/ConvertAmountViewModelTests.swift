//
//  ConvertAmountViewModelTests.swift
//  FlipcashTests
//

import Foundation
import Testing
@testable import FlipcashCore
import FlipcashStore
@testable import Flipcash

@Suite("ConvertAmountViewModel — fee-affordable entry")
@MainActor
struct ConvertAmountViewModelTests {

    private static let jeffySupply: UInt64 = 50_000 * 10_000_000_000
    private static let jeffyQuarks: UInt64 = 2_000 * 10_000_000_000 // ≈ $20 of curve value

    private static func makeContainer(
        holdings: [SessionContainer.Holding],
        currency: CurrencyCode = .usd,
        fx: Double = 1.0
    ) async throws -> SessionContainer {
        let container = try SessionContainer.makeTest(holdings: holdings)

        container.ratesController.configureTestRates(
            balanceCurrency: currency,
            rates: [Rate(fx: Decimal(fx), currency: currency)]
        )
        await container.ratesController.verifiedProtoService.saveRates([
            .freshRate(currencyCode: currency.rawValue.uppercased(), rate: fx)
        ])
        await container.ratesController.verifiedProtoService.saveReserveStates([
            .freshReserve(mint: .jeffy, supplyFromBonding: jeffySupply)
        ])

        return container
    }

    private static func makeViewModel(
        source: StoredBalance,
        container: SessionContainer
    ) -> ConvertAmountViewModel {
        ConvertAmountViewModel(
            sourceBalance: source,
            session: container.session,
            ratesController: container.ratesController
        )
    }

    // MARK: - Converting out of Dollars (fee-free)

    @Test("Converting the whole Dollars balance is left alone — Dollars carry no fee")
    func wholeDollarsBalance_isCorrected() async throws {
        let container = try await Self.makeContainer(holdings: [
            SessionContainer.Holding(mint: .usdf, quarks: 10_000_000), // $10.00
            SessionContainer.Holding(mint: .makeLaunchpad(address: .jeffy, supplyFromBonding: Self.jeffySupply), quarks: Self.jeffyQuarks),
        ])
        let usdf = try #require(container.session.balance(for: .usdf))
        let viewModel = Self.makeViewModel(source: usdf, container: container)
        viewModel.enteredAmount = "10"

        viewModel.correctEntryToAffordable()

        // Nothing is charged on top, so the full balance is convertible.
        #expect(viewModel.enteredAmount == "10")
    }

    @Test("A Dollars entry with room for its fee is left exactly as typed")
    func dollarsEntryWithRoom_isLeftAlone() async throws {
        let container = try await Self.makeContainer(holdings: [
            SessionContainer.Holding(mint: .usdf, quarks: 10_000_000), // $10.00
            SessionContainer.Holding(mint: .makeLaunchpad(address: .jeffy, supplyFromBonding: Self.jeffySupply), quarks: Self.jeffyQuarks),
        ])
        let usdf = try #require(container.session.balance(for: .usdf))
        let viewModel = Self.makeViewModel(source: usdf, container: container)
        viewModel.enteredAmount = "5"

        viewModel.correctEntryToAffordable()

        #expect(viewModel.enteredAmount == "5")
    }

    @Test("The whole Dollars balance clears the affordability gate with no fee on top")
    func correctedEntry_passesTheAffordabilityGate() async throws {
        let container = try await Self.makeContainer(holdings: [
            SessionContainer.Holding(mint: .usdf, quarks: 10_000_000), // $10.00
            SessionContainer.Holding(mint: .makeLaunchpad(address: .jeffy, supplyFromBonding: Self.jeffySupply), quarks: Self.jeffyQuarks),
        ])
        let usdf = try #require(container.session.balance(for: .usdf))
        let viewModel = Self.makeViewModel(source: usdf, container: container)
        viewModel.enteredAmount = "10"
        viewModel.correctEntryToAffordable()

        // The debit is the entry plus its on-top Dollars fee — it must fit the balance.
        let entered = try #require(viewModel.enteredFiat)
        let debit = entered.adding(entered.launchpadSellFee(bps: LaunchpadFee.dollarsFeeBps))
        switch container.session.hasSufficientFunds(for: debit) {
        case .sufficient:
            break
        case .insufficient:
            Issue.record("The whole Dollars balance must be spendable")
        }
    }

    // MARK: - Converting out of a token (fee skimmed from the entry)

    @Test("Converting a whole token balance is left alone — its fee comes out of the entry")
    func wholeTokenBalance_isLeftAlone() async throws {
        let container = try await Self.makeContainer(holdings: [
            SessionContainer.Holding(mint: .makeLaunchpad(address: .jeffy, supplyFromBonding: Self.jeffySupply), quarks: Self.jeffyQuarks),
            SessionContainer.Holding(mint: .usdf, quarks: 10_000_000),
        ])
        let jeffy = try #require(container.session.balance(for: .jeffy))
        let rate = container.ratesController.rateForBalanceCurrency()
        let displayed = jeffy.computeExchangedValue(with: rate)
            .nativeAmount.value.rounded(to: CurrencyCode.usd.maximumFractionDigits)
        let viewModel = Self.makeViewModel(source: jeffy, container: container)
        viewModel.enteredAmount = "\(displayed)"

        viewModel.correctEntryToAffordable()

        #expect(viewModel.enteredAmount == "\(displayed)")
    }
}
