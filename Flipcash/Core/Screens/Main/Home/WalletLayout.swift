//
//  WalletLayout.swift
//  Flipcash
//

import Foundation


/// A block of the wallet tab, top to bottom.
enum WalletSection: Equatable {
    // Today's wallet.
    case balanceHeader
    case appreciation
    case addMoneyRow
    case tokenCards
    case recentActivity
    case tiles
    // The Money layout (node 13729:744).
    case title
    case balance
    case currencyCount
    case actions
}

/// Which wallet the wallet tab draws: today's, or the Group Money redesign's
/// Money screen (node 13729:744), behind ``BetaFlags/Option/groupMoneyUI``.
enum WalletLayout: Equatable {
    case standard
    case money

    init(showsGroupMoney: Bool) {
        self = showsGroupMoney ? .money : .standard
    }

    /// The blocks the tab shows, in order. A block may still draw nothing for
    /// a given state — the Add Money row waits on history, for one.
    var sections: [WalletSection] {
        switch self {
        case .standard:
            [.balanceHeader, .appreciation, .addMoneyRow, .tokenCards, .recentActivity, .tiles]
        case .money:
            [.title, .balance, .currencyCount, .actions, .recentActivity]
        }
    }
}

