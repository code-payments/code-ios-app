//
//  GroupMoneyShellStubs.swift
//  Flipcash
//
//  Placeholders for the Group Money shell's API, so its spec tests compile and
//  fail before anything is built. Every answer here is deliberately wrong.
//  Each climb step replaces a placeholder with the real thing; nothing in the
//  app calls these, and this file is deleted before the work lands.
//

import Foundation
import FlipcashCore

extension BetaFlags.Option {
    static var groupMoneyUI: BetaFlags.Option { .vibrateOnScan }
}

extension BetaFlags {
    static func hasStaffAccess(isStaff: Bool, accessGranted: Bool) -> Bool { false }
    static func developerOptions(isStaff: Bool, accessGranted: Bool) -> [Option] { [] }
    static func showsGroupMoneyUI(isEnabled: Bool, isStaff: Bool, accessGranted: Bool) -> Bool { false }
}

enum HomeTabLayout: Equatable {
    case standard
    case groupMoney

    init(showsGroupMoney: Bool) { self = .standard }
    var barTabs: [HomeTab] { [] }
    var hasSearchTab: Bool { false }
    var initialTab: HomeTab { .scan }
    var searchResultTab: HomeTab { .scan }
    func isReachable(_ tab: HomeTab) -> Bool { false }
    func title(for tab: HomeTab) -> String { "" }
    func iconName(for tab: HomeTab, isSelected: Bool) -> String { "" }
}

enum WalletSection: Equatable {
    case balanceHeader, appreciation, addMoneyRow, tokenCards, recentActivity, tiles
    case title, balance, currencyCount, actions
}

enum WalletLayout: Equatable {
    case standard
    case money

    init(showsGroupMoney: Bool) { self = .standard }
    var sections: [WalletSection] { [.tokenCards, .appreciation, .tiles] }
}

enum MoneyHeaderContent {
    static let title = ""
    static let addMoneyTitle = ""
    static let withdrawTitle = ""
    static func currencyCountText(_ count: Int) -> String { "" }
}

extension AppRouter.Destination {
    static var walletCurrencies: AppRouter.Destination { .withdrawCurrency(nil) }
}

enum MoneyAction {
    case profile, addMoney, withdraw, currencies
    func perform(on router: AppRouter) {}
}

enum MoneyActivityRowContent {
    static func conversationID(
        boostedReaction: Activity.BoostedReaction?,
        requestedPayment: Activity.RequestedPayment?,
        returnedPayment: Activity.ReturnedPayment?
    ) -> ConversationID? { nil }
    static func title(groupName: String?, fallback: String) -> String { "" }
    static func subtitle(name: String?, day: String) -> String { "" }
    static func dayText(for date: Date) -> String { "" }
    static func amountText(_ amount: FiatAmount, signPrefix: String?) -> String { "" }
}
