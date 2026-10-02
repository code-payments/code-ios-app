//
//  BarAccessories.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import CoreGraphics

/// The cards stacked above the composer row, as the bar reports them alongside its height.
public struct BarAccessories: Equatable, Sendable {

    /// A card that can stand above the composer row.
    public enum Kind: Hashable, Sendable {
        case mentions
        case reply
    }

    /// The cards that are open and already measured. A card joins only once it has its height, so
    /// the report that adds it is the one whose height includes it.
    public var open: Set<Kind>

    /// The combined height of cards that have closed but are still mounted while the clip closes
    /// over them.
    public var exitingHeight: CGFloat

    /// The height of the bar under the mention list — the reply strip and the composer row —
    /// which the list's room is measured without.
    ///
    /// Measured from those views rather than taken as the bar less the list: the bar and the list
    /// are measured a pass apart, so the difference moved with the list and fed back into its row
    /// count, and a list under a reply flipped between two sizes without settling.
    public var restHeight: CGFloat

    public init(open: Set<Kind> = [], exitingHeight: CGFloat = 0, restHeight: CGFloat = 0) {
        self.open = open
        self.exitingHeight = exitingHeight
        self.restHeight = restHeight
    }

    /// Two reports combined, as sibling cards report them.
    public func merged(with other: BarAccessories) -> BarAccessories {
        BarAccessories(
            open: open.union(other.open),
            exitingHeight: exitingHeight + other.exitingHeight,
            restHeight: restHeight + other.restHeight
        )
    }
}
