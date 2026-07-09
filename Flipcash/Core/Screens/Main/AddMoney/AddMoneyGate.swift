//
//  AddMoneyGate.swift
//  Flipcash
//

import Foundation
import FlipcashCore

/// Read-only access to the user's USDF reserve balance.
@MainActor
protocol USDFReserveReading: AnyObject {
    func balance(for mint: PublicKey) -> StoredBalance?
}

extension Session: USDFReserveReading {}

/// True when the user holds no USDF reserves to spend on a buy.
@MainActor
func shouldAddMoneyBeforeBuy(session: some USDFReserveReading) -> Bool {
    guard let balance = session.balance(for: .usdf) else { return true }
    return balance.usdf.value == 0
}

/// True when the user's USDF reserves can't cover `launchCost` (purchase +
/// fee). Must agree with the wizard's `reserveBalance` affordability check.
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
    /// Community currency on hand.
    case proceed
    /// USDF but no community currency.
    case discoverCurrencies
    /// No balance at all.
    case addMoney
}

/// Returns where a give-cash entry routes given the user's balances. USDF
/// counts only at displayable value, so the prompt agrees with the balance the
/// wallet renders.
@MainActor
func giveCashGate(session: some GiveBalanceReading, rate: Rate) -> GiveCashGate {
    if session.hasGiveableBalance(for: rate) { return .proceed }
    let hasUSDF = session.balance(for: .usdf)?
        .computeExchangedValue(with: rate)
        .hasDisplayableValue() ?? false
    return hasUSDF ? .discoverCurrencies : .addMoney
}
