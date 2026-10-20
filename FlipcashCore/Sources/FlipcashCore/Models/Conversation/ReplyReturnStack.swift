//
//  ReplyReturnStack.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// The messages a reader tapped reply quotes from on one visit to a chat, newest on top, so the
/// jump-to-bottom button can walk back through them before it goes to the bottom.
///
/// Lives only as long as the open chat. Android's reply return stack applies the same rules.
public struct ReplyReturnStack: Sendable, Equatable {

    /// The origin messages' stable ids, oldest first.
    public private(set) var origins: [String] = []

    public init() {}

    /// Whether there is nowhere to return to.
    public var isEmpty: Bool { origins.isEmpty }

    /// Records a quote tap in `origin`, unless it is already the top entry.
    public mutating func push(origin: String) {
        guard origins.last != origin else { return }
        origins.append(origin)
    }

    /// Removes and returns the newest origin that `exists` still finds in the chat, discarding any
    /// above it that it doesn't. Nil once the stack runs out.
    public mutating func popOrigin(exists: (String) -> Bool) -> String? {
        while let origin = origins.popLast() {
            if exists(origin) { return origin }
        }
        return nil
    }

    /// Drops every top entry the reader has scrolled down to or past, stopping at the first one
    /// they haven't reached.
    public mutating func dropReached(_ isReached: (String) -> Bool) {
        while let origin = origins.last, isReached(origin) {
            origins.removeLast()
        }
    }

    /// Forgets every origin.
    public mutating func clear() {
        origins.removeAll()
    }
}
