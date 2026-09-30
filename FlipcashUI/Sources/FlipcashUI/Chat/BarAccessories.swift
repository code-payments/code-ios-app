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

    /// The mention list's current height, which the transcript's room is measured without.
    public var mentionsHeight: CGFloat

    public init(open: Set<Kind> = [], exitingHeight: CGFloat = 0, mentionsHeight: CGFloat = 0) {
        self.open = open
        self.exitingHeight = exitingHeight
        self.mentionsHeight = mentionsHeight
    }

    /// Two reports combined, as sibling cards report them.
    public func merged(with other: BarAccessories) -> BarAccessories {
        BarAccessories(
            open: open.union(other.open),
            exitingHeight: exitingHeight + other.exitingHeight,
            mentionsHeight: mentionsHeight + other.mentionsHeight
        )
    }
}
