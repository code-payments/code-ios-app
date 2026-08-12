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

    /// True once a completed deposit or buy exists — the "added money" milestone.
    func hasEverAddedMoney() throws -> Bool {
        let a = ActivityTable()
        let funded = [Activity.Kind.deposited.rawValue, Activity.Kind.bought.rawValue]
        return try reader.pluck(
            a.table.filter(funded.contains(a.kind) && a.state == Activity.State.completed.rawValue)
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
