//
//  ConvertAmountViewModelTests.swift
//  FlipcashTests
//

import Foundation
import Testing
@testable import FlipcashCore
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

    // MARK: - Converting out of Dollars (fee charged on top)

    @Test("Converting the whole Dollars balance drops the entry to what the on-top fee leaves")
    func wholeDollarsBalance_isCorrected() async throws {
        let container = try await Self.makeContainer(holdings: [
            .init(mint: .usdf, quarks: 10_000_000), // $10.00
            .init(mint: .makeLaunchpad(address: .jeffy, supplyFromBonding: Self.jeffySupply), quarks: Self.jeffyQuarks),
        ])
        let usdf = try #require(container.session.balance(for: .usdf))
        let viewModel = Self.makeViewModel(source: usdf, container: container)
        viewModel.enteredAmount = "10"

        viewModel.correctEntryToAffordable()

        // $10.00 / 1.01 = $9.90099, floored to the cent so the debit fits.
        #expect(viewModel.enteredAmount == "9.90")
    }

    @Test("A Dollars entry with room for its fee is left exactly as typed")
    func dollarsEntryWithRoom_isLeftAlone() async throws {
        let container = try await Self.makeContainer(holdings: [
            .init(mint: .usdf, quarks: 10_000_000), // $10.00
            .init(mint: .makeLaunchpad(address: .jeffy, supplyFromBonding: Self.jeffySupply), quarks: Self.jeffyQuarks),
        ])
        let usdf = try #require(container.session.balance(for: .usdf))
        let viewModel = Self.makeViewModel(source: usdf, container: container)
        viewModel.enteredAmount = "5"

        viewModel.correctEntryToAffordable()

        #expect(viewModel.enteredAmount == "5")
    }

    @Test("The corrected entry clears the gate that the uncorrected one failed")
    func correctedEntry_passesTheAffordabilityGate() async throws {
        let container = try await Self.makeContainer(holdings: [
            .init(mint: .usdf, quarks: 10_000_000), // $10.00
            .init(mint: .makeLaunchpad(address: .jeffy, supplyFromBonding: Self.jeffySupply), quarks: Self.jeffyQuarks),
        ])
        let usdf = try #require(container.session.balance(for: .usdf))
        let viewModel = Self.makeViewModel(source: usdf, container: container)
        viewModel.enteredAmount = "10"
        viewModel.correctEntryToAffordable()

        // The debit is the entry plus its own 1% — it must now fit the balance.
        let entered = try #require(viewModel.enteredFiat)
        let debit = entered.adding(entered.launchpadSellFee(bps: 100))
        switch container.session.hasSufficientFunds(for: debit) {
        case .sufficient:
            break
        case .insufficient:
            Issue.record("The corrected entry must cover its own fee")
        }
    }

    // MARK: - Converting out of a token (fee skimmed from the entry)

    @Test("Converting a whole token balance is left alone — its fee comes out of the entry")
    func wholeTokenBalance_isLeftAlone() async throws {
        let container = try await Self.makeContainer(holdings: [
            .init(mint: .makeLaunchpad(address: .jeffy, supplyFromBonding: Self.jeffySupply), quarks: Self.jeffyQuarks),
            .init(mint: .usdf, quarks: 10_000_000),
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
