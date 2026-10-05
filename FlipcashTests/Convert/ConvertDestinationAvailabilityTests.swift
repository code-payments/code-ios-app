//
//  ConvertDestinationAvailabilityTests.swift
//  FlipcashTests
//

import Foundation
import Testing
@testable import FlipcashCore
import FlipcashStore
@testable import Flipcash

@Suite("Convert availability on the currency info screen")
@MainActor
struct ConvertDestinationAvailabilityTests {

    private static let jeffySupply: UInt64 = 50_000 * 10_000_000_000
    private static let jeffyQuarks: UInt64 = 2_000 * 10_000_000_000 // ≈ $20 of curve value

    /// Reserves are seeded in every case so a disabled result comes from the
    /// holdings, not from a curve that can't be priced.
    private static func makeContainer(holdings: [SessionContainer.Holding]) async throws -> SessionContainer {
        let container = try SessionContainer.makeTest(holdings: holdings)

        container.ratesController.configureTestRates(
            balanceCurrency: .usd,
            rates: [Rate(fx: 1, currency: .usd)]
        )
        await container.ratesController.verifiedProtoService.saveRates([
            .freshRate(currencyCode: "USD", rate: 1)
        ])
        await container.ratesController.verifiedProtoService.saveReserveStates([
            .freshReserve(mint: .jeffy, supplyFromBonding: jeffySupply)
        ])

        return container
    }

    private static func canConvert(_ mint: PublicKey, in container: SessionContainer) -> Bool {
        CurrencyInfoViewModel(
            mint: mint,
            session: container.session,
            database: container.database,
            ratesController: container.ratesController
        ).canConvert
    }

    private static let jeffy = MintMetadata.makeLaunchpad(address: .jeffy, supplyFromBonding: jeffySupply)

    @Test("Dollars only: Convert on the Dollars screen is disabled")
    func dollarsOnly_isDisabled() async throws {
        let container = try await Self.makeContainer(holdings: [
            SessionContainer.Holding(mint: .usdf, quarks: 10_000_000),
        ])

        #expect(Self.canConvert(.usdf, in: container) == false)
    }

    @Test("Dollars plus a held currency: Convert is enabled and opens on that currency")
    func dollarsAndHeldCurrency_isEnabled() async throws {
        let container = try await Self.makeContainer(holdings: [
            SessionContainer.Holding(mint: .usdf, quarks: 10_000_000),
            SessionContainer.Holding(mint: Self.jeffy, quarks: Self.jeffyQuarks),
        ])

        #expect(Self.canConvert(.usdf, in: container))

        let usdf = try #require(container.session.balance(for: .usdf))
        let convert = ConvertAmountViewModel(
            sourceBalance: usdf,
            session: container.session,
            ratesController: container.ratesController
        )
        #expect(convert.destinationMint == .jeffy)
    }

    @Test("Only other holding is a zero balance: Convert is disabled")
    func zeroBalanceOtherHolding_isDisabled() async throws {
        let container = try await Self.makeContainer(holdings: [
            SessionContainer.Holding(mint: .usdf, quarks: 10_000_000),
            SessionContainer.Holding(mint: Self.jeffy, quarks: 0),
        ])

        #expect(Self.canConvert(.usdf, in: container) == false)
    }

    @Test("No balances yet: Convert on the Dollars screen is disabled")
    func noBalances_isDisabled() async throws {
        let container = try await Self.makeContainer(holdings: [])

        #expect(Self.canConvert(.usdf, in: container) == false)
    }

    @Test("Another currency's screen keeps Convert enabled with nothing else held")
    func nonDollarsScreen_isEnabled() async throws {
        let container = try await Self.makeContainer(holdings: [
            SessionContainer.Holding(mint: Self.jeffy, quarks: Self.jeffyQuarks),
        ])

        #expect(Self.canConvert(.jeffy, in: container))
    }
}
