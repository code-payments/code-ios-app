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

    /// How many recent activities the tab lists: a three-row preview on today's wallet, and on
    /// Money enough to run past the bottom of the screen, where the section fills what is left.
    var recentActivityLimit: Int {
        switch self {
        case .standard: 3
        case .money:    20
        }
    }

    /// Whether closing a card puts the wallet back at full opacity in the step
    /// that removes the page, rather than fading it in afterwards. The Money
    /// layout has no deck to carry the card home, so a fade there leaves a frame
    /// with nothing drawn between the page going and Money arriving.
    var restoresContentWhenCardCloses: Bool {
        switch self {
        case .standard: false
        case .money:    true
        }
    }
}

