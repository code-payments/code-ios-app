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


/// Read access to every balance the launch gate weighs.
@MainActor
protocol LaunchBalanceReading: AnyObject {
    var balances: [StoredBalance] { get }
}

extension Session: LaunchBalanceReading {}

/// True when `balance` alone can pay `launchCost`. USDF compares exactly (the
/// server has no tolerance on the core path, so display-rounding must not widen
/// it); a launchpad balance compares its display-rounded USD sell value, which
/// mirrors the server's ± half-cent acceptance window.
@MainActor
func canPayLaunchCost(_ balance: StoredBalance, launchCost: TokenAmount) -> Bool {
    if balance.mint == .usdf {
        return balance.usdf.value >= launchCost.decimalValue
    }
    return balance.usdf.value.rounded(to: CurrencyCode.usd.maximumFractionDigits) >= launchCost.decimalValue
}

/// True when no single balance can pay `launchCost` (purchase + fee), so the
/// user must add money before launching. Shares `canPayLaunchCost` with the
/// payment picker's row enablement, so the gate and picker never disagree.
@MainActor
func shouldAddMoneyBeforeLaunch(session: some LaunchBalanceReading, launchCost: TokenAmount) -> Bool {
    !session.balances.contains { canPayLaunchCost($0, launchCost: launchCost) }
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
