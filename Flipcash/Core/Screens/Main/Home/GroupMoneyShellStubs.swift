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
