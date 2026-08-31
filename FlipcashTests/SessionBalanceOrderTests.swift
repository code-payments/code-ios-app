//
//  SessionBalanceOrderTests.swift
//  FlipcashTests
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@Suite("Wallet card-stack order") @MainActor
struct SessionBalanceOrderTests {

    /// Supply chosen so every amount below sells inside a single 100-token
    /// pricing step, making the curve's USD result exact and hand-checkable.
    private static let supply: UInt64 = 50_099 * 10_000_000_000

    /// Launchpad quark amounts and the USD value the curve returns for each at
    /// `supply`. The first two straddle reserves' exact 1.000000 while both
    /// still display as $1.00; only the digits past the cent separate them.
    private static let justUnderADollar: UInt64 = 956_706_288_028  // $0.999600
    private static let justOverADollar: UInt64  = 957_471_959_327  // $1.000400
    private static let ninetyNineCents: UInt64  = 947_518_232_441  // $0.990000
    private static let oneOhOne: UInt64         = 966_660_014_914  // $1.010000

    private static func makeContainer(dadCashQuarks: UInt64) throws -> SessionContainer {
        try SessionContainer.makeTest(holdings: [
            // Reserves sit at exactly 1.000000 — six decimals, no curve.
            .init(mint: .usdf, quarks: 1_000_000),
            .init(
                mint: .makeLaunchpad(
                    address: .jeffy,
                    name: "Dad Cash",
                    supplyFromBonding: supply
                ),
                quarks: dadCashQuarks
            ),
        ])
    }

    /// Rewrites Dad Cash's holding and waits for the session to re-read it —
    /// the price refresh that used to re-decide the deck's order.
    private static func refresh(
        _ container: SessionContainer,
        dadCashQuarks: UInt64
    ) async throws {
        try container.database.transaction { db in
            try db.insertBalance(quarks: dadCashQuarks, mint: .jeffy, costBasis: 0, date: .now)
        }
        NotificationCenter.default.post(name: .databaseDidChange, object: nil)

        try await waitUntil(container.session) { session in
            session.balances.first { $0.mint == .jeffy }?.quarks == dadCashQuarks
        }
    }

    @Test("Cards displaying the same figure hold their order across a refresh")
    func sameDisplayedFigure_orderHoldsAcrossRefresh() async throws {
        let container = try Self.makeContainer(dadCashQuarks: Self.justUnderADollar)

        // Both cards read $1.00; Dad Cash is a hair under a dollar.
        #expect(container.session.balances.map(\.name) == ["Dad Cash", "USDF"])

        // A refresh nudges Dad Cash past reserves in the sixth decimal. Nothing
        // a user can see has changed, so nothing on screen may move.
        try await Self.refresh(container, dadCashQuarks: Self.justOverADollar)
        #expect(container.session.balances.map(\.name) == ["Dad Cash", "USDF"])
    }

    @Test("A one-cent difference still orders the deck")
    func visibleDifference_ordersByValue() async throws {
        let container = try Self.makeContainer(dadCashQuarks: Self.ninetyNineCents)

        #expect(container.session.balances.map(\.name) == ["USDF", "Dad Cash"])

        try await Self.refresh(container, dadCashQuarks: Self.oneOhOne)
        #expect(container.session.balances.map(\.name) == ["Dad Cash", "USDF"])
    }
}
