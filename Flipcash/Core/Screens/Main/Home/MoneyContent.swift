//
//  MoneyContent.swift
//  Flipcash
//

import Foundation

/// The Money screen's fixed copy (node 13729:744).
enum MoneyHeaderContent {
    static let title = String(localized: "Money", comment: "Money tab title")
    static let addMoneyTitle = String(localized: "Add Money", comment: "Money tab button")
    static let withdrawTitle = String(localized: "Withdraw", comment: "Money tab button")
    static let recentActivityTitle = String(localized: "Recent Activity", comment: "Money tab section header")

    /// The line under the balance that opens the currencies held: "1 currency",
    /// "54 currencies".
    static func currencyCountText(_ count: Int) -> String {
        if count == 1 {
            return String(localized: "1 currency", comment: "Money tab: number of currencies held, singular")
        }
        return String(localized: "\(count) currencies", comment: "Money tab: number of currencies held, plural")
    }
}

/// What a control on the Money screen does, as a router call. Each one goes
/// where the matching control on today's wallet goes.
enum MoneyAction {
    /// The avatar: You, as tapping the You tab would.
    case profile
    /// Add Money: today's Add Money row and Add Dollars tile.
    case addMoney
    /// Withdraw: today's Withdraw Dollars tile.
    case withdraw
    /// "N currencies": the currencies held.
    case currencies

    func perform(on router: AppRouter) {
        switch self {
        case .profile:
            router.showOwnTipCard()
        case .addMoney:
            router.presentAddMoney(.general, source: .balance)
        case .withdraw:
            router.push(.withdrawCurrency(nil))
        case .currencies:
            router.push(.walletCurrencies)
        }
    }
}
