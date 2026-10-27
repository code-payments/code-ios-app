//
//  CurrencyInfoActions.swift
//  Flipcash
//

import Foundation

/// What the Currency Info action row and its More sheet offer in each state. Kept apart from the
/// views so the per-state rules (and Android's matching ones) can be checked without rendering.
nonisolated enum CurrencyInfoActions {

    enum Tile: Hashable, Sendable {
        case send
        case buy
        /// The lone tile for a currency that isn't held; the same buy flow, worded for a first purchase.
        case buyIn
        case transactions
        case more
    }

    enum MoreRow: Hashable, Sendable {
        case convert
        case withdraw
        case deposit
    }

    /// Held non-USDF: Send, Buy, Transactions, More. USDF drops Buy (nothing to buy it with); a
    /// currency that isn't held offers only Buy In.
    static func tiles(isOwned: Bool, isUSDF: Bool) -> [Tile] {
        guard isOwned else { return [.buyIn] }
        return isUSDF ? [.send, .transactions, .more] : [.send, .buy, .transactions, .more]
    }

    /// Convert, Withdraw and Deposit. USDF has no per-currency deposit address, so it stops at two.
    static func moreRows(isUSDF: Bool) -> [MoreRow] {
        isUSDF ? [.convert, .withdraw] : [.convert, .withdraw, .deposit]
    }

    static func subtitle(for row: MoreRow, name: String) -> String {
        switch row {
        case .convert:  "Convert \(name) to another community currency on Flipcash"
        case .withdraw: "Withdraw \(name) to a different Solana crypto wallet"
        case .deposit:  "Deposit \(name) from a different Solana crypto wallet"
        }
    }

    static func title(for row: MoreRow) -> String {
        switch row {
        case .convert:  "Convert"
        case .withdraw: "Withdraw"
        case .deposit:  "Deposit"
        }
    }
}
