//
//  AddMoneyContext.swift
//  Flipcash
//

import Foundation

/// Why the Add Money flow was opened. Selects the "No Balance Yet" subtitle;
/// the flow itself is currency-agnostic (it only deposits USDF).
nonisolated enum AddMoneyContext: Hashable, Sendable {
    case buyCurrency
    case createCurrency
    case giveCash
    /// Direct entry (Wallet / Settings "Add Money" buttons) — no gating
    /// dialog precedes the sheet, so the subtitle is never shown.
    case general

    var noBalanceSubtitle: String {
        switch self {
        case .buyCurrency:    "Add money to buy currencies"
        case .createCurrency: "Add money to create a currency"
        case .giveCash:       "Add money to give cash"
        case .general:        "Add money to get started"
        }
    }
}
