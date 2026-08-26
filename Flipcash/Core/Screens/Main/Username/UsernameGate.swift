//
//  UsernameGate.swift
//  Flipcash
//

import Foundation
import FlipcashCore

/// The one balance the username gate weighs: everything the user holds, summed
/// and expressed in USD.
@MainActor
protocol UsernameBalanceReading: AnyObject {
    var totalBalance: ExchangedFiat { get }
}

extension Session: UsernameBalanceReading {}

/// Where the username entry point leads, and — short of the minimum — how far
/// the balance has to go.
enum UsernameGate: Equatable {
    /// The requirement is met, or there isn't one — open the claim screen.
    case proceed
    /// Short of the minimum. Carries the minimum and the shortfall so the
    /// progress card can name both, and `fraction` — the balance's progress
    /// toward the minimum — so it can size its bar without a second
    /// balance-vs-minimum calculation of its own.
    case addMoney(minimum: FiatAmount, shortfall: FiatAmount, fraction: Double)

    /// How far the balance is toward the minimum, clamped to `[0, 1]`. Always
    /// `1` on `.proceed` — met or waived, there is nothing left to close.
    var fraction: Double {
        switch self {
        case .proceed:
            return 1
        case .addMoney(_, _, let fraction):
            return fraction
        }
    }
}

/// Returns where the username entry point leads, given the user's balances and
/// the server's minimum (`UserFlags.usernameMinBalance`, nil when flags haven't
/// loaded).
///
/// The comparison is cumulative and USD-denominated, which is what the flag
/// documents: every mint counts, and the flag's USDF mint is the denomination
/// rather than the account to measure. `Session.hasSufficientFunds(for:)` is
/// per-mint and answers a different question; comparing quarks would measure a
/// real threshold against `ExchangedFiat.total(rate:)`'s documented
/// USDF-minted placeholder.
///
/// Nothing is debited — this is a holding requirement, so there is no fee and
/// no affordability check.
///
/// A zero minimum proceeds. The flag defaults to zero when the server omits it
/// (`UserFlagsUsernameMinBalanceTests` pins that), and the server owns the
/// number, so there is no client-side fallback to fall back to.
///
/// A nil minimum — flags not loaded yet — proceeds too. That is deliberately
/// fail-open, and safe because the server enforces the same threshold on
/// `SetUsername` and returns `ErrorProfile.insufficientBalance`. Someone who
/// races the flags reaches the claim screen and is turned back there, rather
/// than being told they don't qualify on the strength of a number the client
/// hasn't got yet.
///
/// The comparison is exact — no rounding to display precision. `canPayLaunchCost`
/// makes the same call for the same reason: the server has no tolerance here,
/// so widening the client check would only move the rejection later, after the
/// user has typed a handle.
@MainActor
func usernameGate(session: some UsernameBalanceReading, minimum: TokenAmount?) -> UsernameGate {
    guard let minimum, minimum.quarks > 0 else { return .proceed }

    let required = FiatAmount.usd(minimum.decimalValue)
    let balance = session.totalBalance.usdfValue
    guard balance >= required else {
        let shortfall = required - balance
        let fraction = (balance.value / required.value).doubleValue
        return .addMoney(minimum: required, shortfall: shortfall, fraction: max(0, min(1, fraction)))
    }
    return .proceed
}
