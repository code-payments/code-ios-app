//
//  Database+Onboarding.swift
//  Flipcash
//

import Foundation
import FlipcashCore
import SQLite

/// The durable-history check behind the wallet's new-user Add Money row. It
/// reads the event history (not the current balance), so the row stays hidden
/// after the user later spends the balance.
nonisolated extension Database {

    /// Activity kinds that bring money *in* from outside the user's own
    /// holdings: an on-ramp buy, an external deposit, a tip received, and a
    /// pool distribution. `sold`/`swapped` are excluded — they move value
    /// between tokens the user already holds rather than adding any.
    private static let incomingKinds: [Int] = [
        Activity.Kind.bought.rawValue,
        Activity.Kind.deposited.rawValue,
        Activity.Kind.received.rawValue,
        Activity.Kind.distributed.rawValue,
    ]

    /// True once any completed incoming-money activity exists — the "added
    /// money" milestone.
    public func hasEverAddedMoney() throws -> Bool {
        let a = ActivityTable()
        return try reader.pluck(
            a.table.filter(
                Self.incomingKinds.contains(a.kind) && a.state == Activity.State.completed.rawValue
            )
        ) != nil
    }
}
