//
//  ResolveInitialBalanceTests.swift
//  FlipcashTests
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

/// `includingDollars` is `BetaFlags.allowsDollarsGive` at every call site: false
/// on the old UI, which has no Dollars give affordance anywhere, true on the new.
@MainActor
@Suite("RatesController.resolveInitialBalance")
struct ResolveInitialBalanceTests {

    @Test("A Dollars-only account resolves to Dollars once Dollars can be given")
    func dollarsOnly_withDollars_resolvesToUSDF() throws {
        let container = try SessionContainer.makeTest(holdings: [
            .init(mint: .usdf, quarks: 25_000_000), // $25
        ])
        container.ratesController.selectedTokenMint = nil

        let resolved = container.ratesController.resolveInitialBalance(
            mint: nil,
            session: container.session,
            includingDollars: true
        )

        #expect(resolved?.stored.mint == .usdf)
    }

    @Test("A Dollars-only account resolves to nothing while Dollars can't be given")
    func dollarsOnly_withoutDollars_resolvesToNil() throws {
        let container = try SessionContainer.makeTest(holdings: [
            .init(mint: .usdf, quarks: 25_000_000),
        ])
        container.ratesController.selectedTokenMint = nil

        let resolved = container.ratesController.resolveInitialBalance(
            mint: nil,
            session: container.session,
            includingDollars: false
        )

        #expect(resolved == nil)
    }

    @Test("Dollars that displays as $0.00 can't fund anything, so it resolves to nothing")
    func dollarsDust_resolvesToNil() throws {
        let container = try SessionContainer.makeTest(holdings: [
            .init(mint: .usdf, quarks: 1_000), // $0.001
        ])
        container.ratesController.selectedTokenMint = nil

        let resolved = container.ratesController.resolveInitialBalance(
            mint: nil,
            session: container.session,
            includingDollars: true
        )

        #expect(resolved == nil)
    }

    @Test("The auto-pick prefers a community currency over a larger Dollars balance")
    func autoPick_prefersCommunityCurrency() throws {
        let container = try makeMixedContainer()
        container.ratesController.selectedTokenMint = nil

        let resolved = container.ratesController.resolveInitialBalance(
            mint: nil,
            session: container.session,
            includingDollars: true
        )

        #expect(resolved?.stored.mint == .jeffy)
    }

    @Test("A parked USDF selection isn't read as an intentional Dollars choice")
    func staleUSDFSelection_prefersCommunityCurrency() throws {
        // `Session.ensureValidTokenSelection` parks the global selection on the
        // highest balance, which is routinely USDF — honoring it would open every
        // flow in Dollars.
        let container = try makeMixedContainer()
        container.ratesController.selectedTokenMint = .usdf

        let resolved = container.ratesController.resolveInitialBalance(
            mint: nil,
            session: container.session,
            includingDollars: true
        )

        #expect(resolved?.stored.mint == .jeffy)
    }

    @Test("An explicit mint wins over the auto-pick")
    func explicitMint_wins() throws {
        let container = try makeMixedContainer()
        container.ratesController.selectedTokenMint = nil

        let resolved = container.ratesController.resolveInitialBalance(
            mint: .usdf,
            session: container.session,
            includingDollars: true
        )

        #expect(resolved?.stored.mint == .usdf)
    }

    // MARK: - Helpers

    /// $100k of Dollars — which sorts first — alongside a funded community currency.
    private func makeMixedContainer() throws -> SessionContainer {
        try SessionContainer.makeTest(holdings: [
            .init(mint: .usdf, quarks: 100_000_000_000),
            .init(
                mint: .makeLaunchpad(
                    address: .jeffy,
                    supplyFromBonding: 1_000_000 * 10_000_000_000
                ),
                quarks: 10 * 10_000_000_000
            ),
        ])
    }
}
