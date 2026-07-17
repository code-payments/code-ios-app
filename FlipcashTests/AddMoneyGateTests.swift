//
//  AddMoneyGateTests.swift
//  FlipcashTests
//

import Foundation
import Testing
@testable import Flipcash
import FlipcashCore

@Suite("AddMoneyGate") @MainActor
struct AddMoneyGateTests {

    /// Builds a USDF `StoredBalance` holding `quarks` (6-decimal) of reserves.
    func makeUSDFBalance(quarks: UInt64) throws -> StoredBalance {
        try StoredBalance(
            quarks: quarks,
            symbol: "USDF",
            name: "USDF Coin",
            supplyFromBonding: nil,
            sellFeeBps: nil,
            mint: .usdf,
            vmAuthority: nil,
            updatedAt: Date(),
            imageURL: nil,
            costBasis: 0
        )
    }

    // Buy has no pre-gate anymore: the amount screen always opens and its
    // action button becomes an Add Money CTA when nothing is spendable
    // (covered by BuyAmountViewModelTests).

    // MARK: - Launch

    /// $20 launch cost (USDF, 6 decimals) — the default new-currency purchase
    /// amount the wizard charges.
    private var launchCost: TokenAmount { TokenAmount(quarks: 20_000_000, mint: .usdf) }

    @Test("Launch pre-check adds money when there is no USDF balance")
    func launch_noBalance_addsMoney() {
        let session = MockSession()
        session.usdfReserveBalance = nil
        #expect(shouldAddMoneyBeforeLaunch(session: session, launchCost: launchCost) == true)
    }

    @Test("Launch pre-check adds money when reserves fall short of the launch cost")
    func launch_belowCost_addsMoney() throws {
        let session = MockSession()
        session.usdfReserveBalance = try makeUSDFBalance(quarks: 10_000_000)
        #expect(shouldAddMoneyBeforeLaunch(session: session, launchCost: launchCost) == true)
    }

    @Test("Launch pre-check proceeds when reserves cover the launch cost")
    func launch_atCost_proceeds() throws {
        let session = MockSession()
        session.usdfReserveBalance = try makeUSDFBalance(quarks: 20_000_000)
        #expect(shouldAddMoneyBeforeLaunch(session: session, launchCost: launchCost) == false)
    }

    // MARK: - Give / send cash

    @Test("Give gate proceeds when a community currency is on hand")
    func give_communityCurrency_proceeds() {
        let session = MockSession()
        session.giveableBalanceExists = true
        #expect(giveCashGate(session: session, rate: .oneToOne) == .proceed)
    }

    @Test("Give gate routes to Discover when only USDF is on hand")
    func give_usdfOnly_discovers() throws {
        let session = MockSession()
        session.usdfReserveBalance = try makeUSDFBalance(quarks: 1_000_000)
        #expect(giveCashGate(session: session, rate: .oneToOne) == .discoverCurrencies)
    }

    @Test("Give gate routes to Add Money when there is no balance at all")
    func give_noBalance_addsMoney() {
        let session = MockSession()
        #expect(giveCashGate(session: session, rate: .oneToOne) == .addMoney)
    }

    @Test("Give gate treats USDF that displays as $0.00 as no balance")
    func give_dustUSDF_addsMoney() throws {
        let session = MockSession()
        session.usdfReserveBalance = try makeUSDFBalance(quarks: 1_000) // $0.001
        #expect(giveCashGate(session: session, rate: .oneToOne) == .addMoney)
    }
}
