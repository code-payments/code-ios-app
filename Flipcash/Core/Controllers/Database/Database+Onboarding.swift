//
//  Database+Onboarding.swift
//  Flipcash
//

import Foundation
import FlipcashCore
import SQLite

/// Durable-history checks backing the wallet onboarding funnel. These read the
/// event history (not the current balance), so a milestone stays complete even
/// after the user later spends the balance — mirroring Android.
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
    func hasEverAddedMoney() throws -> Bool {
        let a = ActivityTable()
        return try reader.pluck(
            a.table.filter(
                Self.incomingKinds.contains(a.kind) && a.state == Activity.State.completed.rawValue
            )
        ) != nil
    }

    /// True once the caller has *sent* a tip — the "scanned a tip card" milestone.
    /// Received tips don't count, so it's scoped to `senderId == selfUserID`.
    func hasEverTipped(selfUserID: UserID) throws -> Bool {
        let m = ConversationMessageTable()
        // cashAction 1 == tipped (see ConversationMessageTable.cashAction).
        return try reader.pluck(
            m.table.filter(m.cashAction == 1 && m.senderId == selfUserID)
        ) != nil
    }
}
