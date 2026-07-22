//
//  AddMoneyContext.swift
//  Flipcash
//

import Foundation

/// Why the Add Money flow was opened; selects the "No Balance Yet" subtitle.
nonisolated enum AddMoneyContext: Hashable, Sendable {
    case buyCurrency
    case createCurrency
    case giveCash
    case sendTips
    /// Direct entry — no gating dialog precedes the sheet.
    case general

    var noBalanceSubtitle: String {
        switch self {
        case .buyCurrency:    "Add money to buy currencies"
        case .createCurrency: "Add money to create a currency"
        case .giveCash:       "Add money to give cash"
        case .sendTips:       "Add money to send tips"
        case .general:        "Add money to get started"
        }
    }
}
