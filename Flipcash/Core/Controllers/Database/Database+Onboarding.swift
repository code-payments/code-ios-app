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

    /// True once the caller has *sent* a tip — the "scanned a tip card"
    /// milestone. Either source proves it, because neither is complete alone:
    /// the activity feed re-syncs in full from the server on every login, while
    /// chat messages sync lazily per conversation, so an account signed into on
    /// a fresh database has activity long before it has any messages.
    func hasEverTipped(selfUserID: UserID) throws -> Bool {
        try hasEverSentTipActivity() || hasEverSentTipMessage(selfUserID: selfUserID)
    }

    /// A completed outgoing direct send — the activity a tip writes to the
    /// history feed. `cashLink` is excluded: an unclaimed link is a send to
    /// nobody, not a tip given.
    private func hasEverSentTipActivity() throws -> Bool {
        let a = ActivityTable()
        return try reader.pluck(
            a.table.filter(
                a.kind == Activity.Kind.gave.rawValue && a.state == Activity.State.completed.rawValue
            )
        ) != nil
    }

    /// A tip this user sent in a chat. Received tips don't count, so it's scoped
    /// to `senderId == selfUserID`.
    private func hasEverSentTipMessage(selfUserID: UserID) throws -> Bool {
        let m = ConversationMessageTable()
        // cashAction 1 == tipped (see ConversationMessageTable.cashAction).
        return try reader.pluck(
            m.table.filter(m.cashAction == 1 && m.senderId == selfUserID)
        ) != nil
    }
}
