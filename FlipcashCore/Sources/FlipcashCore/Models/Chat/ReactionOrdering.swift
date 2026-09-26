//
//  ReactionOrdering.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// The order pills are shown in: boost total descending, then count descending, then the emoji's
/// UTF-8 bytes ascending.
///
/// The last tiebreak matches the server, which sorts summaries with Go's bytewise string compare
/// (`flipcash2-server` `messaging/dynamodb/store.go:2277`). Swift's `String <` compares by Unicode
/// canonical ordering instead, which disagrees with byte order for some multi-scalar emoji, so it
/// must not be used here.
public enum ReactionOrdering {

    /// Returns whether `lhs` is shown before `rhs`.
    public static func areInIncreasingOrder(_ lhs: ReactionPill, _ rhs: ReactionPill) -> Bool {
        let lhsBoost = lhs.boost?.total ?? 0
        let rhsBoost = rhs.boost?.total ?? 0
        if lhsBoost != rhsBoost { return lhsBoost > rhsBoost }
        if lhs.count != rhs.count { return lhs.count > rhs.count }
        return lhs.emoji.utf8.lexicographicallyPrecedes(rhs.emoji.utf8)
    }

    /// Returns `pills` in display order.
    public static func sorted(_ pills: some Sequence<ReactionPill>) -> [ReactionPill] {
        pills.sorted(by: areInIncreasingOrder)
    }
}
