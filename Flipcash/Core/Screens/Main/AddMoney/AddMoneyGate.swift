//
//  AddMoneyGate.swift
//  Flipcash
//

import Foundation
import FlipcashCore

/// Read-only access to the user's USDF reserve balance — the single input the
/// buy/launch "Add Money" pre-checks need. Both `Session` and the test
/// `MockSession` conform, so the gate functions stay unit-testable without
/// standing up a live session.
@MainActor
protocol USDFReserveReading: AnyObject {
    func balance(for mint: PublicKey) -> StoredBalance?
}

extension Session: USDFReserveReading {}

/// True when the user holds no USDF reserves to spend on a buy — the Buy button
/// must route through "Add Money" first. False when reserves exist and the buy
/// amount sheet can open directly.
@MainActor
func shouldAddMoneyBeforeBuy(session: some USDFReserveReading) -> Bool {
    guard let balance = session.balance(for: .usdf) else { return true }
    return balance.usdf.value == 0
}

/// True when the user's USDF reserves can't cover `launchCost` (the currency
/// launch's purchase + fee) — "Get Started" must route through "Add Money"
/// first. Mirrors the wizard's `reserveBalance` affordability check so the gate
/// and the reserves-only launch path agree on the threshold.
@MainActor
func shouldAddMoneyBeforeLaunch(session: some USDFReserveReading, launchCost: TokenAmount) -> Bool {
    guard let balance = session.balance(for: .usdf) else { return true }
    return balance.usdf.value < launchCost.decimalValue
}

/// The balance inputs the give/send cash gate needs — `USDFReserveReading`
/// plus the community-currency predicate.
@MainActor
protocol GiveBalanceReading: USDFReserveReading {
    func hasGiveableBalance(for rate: Rate) -> Bool
}

extension Session: GiveBalanceReading {}

/// Where a "give cash" entry (Cash tab, in-chat Send, give deeplink) routes.
enum GiveCashGate: Equatable {
    /// Community currency on hand — enter the flow.
    case proceed
    /// USDF but no community currency — cash is given in community
    /// currencies, so the next step is Discover, not Add Money.
    case discoverCurrencies
    /// Nothing at all — Add Money.
    case addMoney
}

/// Cash is given in community currencies. "Non-zero USDF" means a displayable
/// value, so the prompt always agrees with the balance the wallet renders.
@MainActor
func giveCashGate(session: some GiveBalanceReading, rate: Rate) -> GiveCashGate {
    if session.hasGiveableBalance(for: rate) { return .proceed }
    let hasUSDF = session.balance(for: .usdf)?
        .computeExchangedValue(with: rate)
        .hasDisplayableValue() ?? false
    return hasUSDF ? .discoverCurrencies : .addMoney
}
