//
//  ReadProgress.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// How far one visit to a chat has read: the newest message someone else sent that has been on
/// screen, reported only when it moves past everything reported before it.
///
/// The READ pointer follows what the reader has seen rather than what has arrived. Android's
/// `MessageReadReporter` applies the same rule.
public struct ReadProgress: Sendable, Equatable {

    /// A message row on screen, as the rule sees it.
    public struct VisibleMessage: Sendable, Equatable {
        public let id: MessageID
        public let isFromSelf: Bool

        public init(id: MessageID, isFromSelf: Bool) {
            self.id = id
            self.isFromSelf = isFromSelf
        }
    }

    /// The highest id reported so far this visit, or nil before the first report.
    public private(set) var reported: MessageID?

    public init() {}

    /// The newest message in `visible` that someone else sent, or nil when there is none.
    ///
    /// A deleted message counts: its tombstone is a row the reader has scrolled past. The viewer's
    /// own messages never do, since sending one is not reading it.
    public static func highestSeenInbound(_ visible: some Sequence<VisibleMessage>) -> MessageID? {
        visible.lazy.filter { !$0.isFromSelf }.map(\.id).max()
    }

    /// Records the rows now on screen, returning the id to report when it beats every earlier report
    /// this visit, and nil otherwise.
    public mutating func advance(seeing visible: some Sequence<VisibleMessage>) -> MessageID? {
        guard let seen = Self.highestSeenInbound(visible) else { return nil }
        if let reported, seen <= reported { return nil }
        reported = seen
        return seen
    }
}
