//
//  FollowArchiveTrackerTests.swift
//  FlipcashCoreTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
@testable import FlipcashCore

/// `FollowArchive` seq and ack bookkeeping. The Android app keeps the same rules, so a case that
/// changes here changes there.
@Suite("Follow archive tracker")
struct FollowArchiveTrackerTests {

    @Test("Each request on a stream carries the next seq")
    func seqIncreases() {
        var tracker = FollowArchiveTracker()
        _ = tracker.streamOpened()

        #expect(tracker.setFollow(true, streamIsOpen: true) == .init(follow: true, seq: 1))
        #expect(tracker.setFollow(false, streamIsOpen: true) == .init(follow: false, seq: 2))
        #expect(tracker.setFollow(true, streamIsOpen: true) == .init(follow: true, seq: 3))
    }

    @Test("Asking for the state already wanted sends nothing")
    func unchangedSendsNothing() {
        var tracker = FollowArchiveTracker()
        _ = tracker.streamOpened()

        #expect(tracker.setFollow(false, streamIsOpen: true) == nil)
        _ = tracker.setFollow(true, streamIsOpen: true)
        #expect(tracker.setFollow(true, streamIsOpen: true) == nil)
    }

    @Test("ON(1), OFF(2): the ack for 1 is stale, the ack for 2 stops following without a re-read")
    func staleAckIgnored() {
        var tracker = FollowArchiveTracker()
        _ = tracker.streamOpened()
        _ = tracker.setFollow(true, streamIsOpen: true)
        _ = tracker.setFollow(false, streamIsOpen: true)

        #expect(tracker.acknowledge(seq: 1) == .stale)
        #expect(tracker.acknowledge(seq: 2) == .notFollowing)
    }

    @Test("The ack for the latest ON counts once")
    func latestAckCountsOnce() {
        var tracker = FollowArchiveTracker()
        _ = tracker.streamOpened()
        _ = tracker.setFollow(true, streamIsOpen: true)

        #expect(tracker.acknowledge(seq: 1) == .following)
        #expect(tracker.acknowledge(seq: 1) == .stale)
    }

    @Test("An ack for a seq never sent is stale")
    func unknownSeqIsStale() {
        var tracker = FollowArchiveTracker()
        _ = tracker.streamOpened()
        #expect(tracker.acknowledge(seq: 1) == .stale)

        _ = tracker.setFollow(true, streamIsOpen: true)
        #expect(tracker.acknowledge(seq: 2) == .stale)
    }

    @Test("A reconnect while following restarts the seq and re-sends ON right away")
    func reconnectResendsFollow() {
        var tracker = FollowArchiveTracker()
        _ = tracker.streamOpened()
        _ = tracker.setFollow(true, streamIsOpen: true)
        _ = tracker.setFollow(false, streamIsOpen: true)
        _ = tracker.setFollow(true, streamIsOpen: true)

        #expect(tracker.streamOpened() == .init(follow: true, seq: 1))
        // An ack from the dropped stream for its seq 3 does not count on the new one.
        #expect(tracker.acknowledge(seq: 3) == .stale)
        #expect(tracker.acknowledge(seq: 1) == .following)
    }

    @Test("A stream that opens unfollowed sends nothing")
    func openUnfollowedSendsNothing() {
        var tracker = FollowArchiveTracker()
        #expect(tracker.streamOpened() == nil)

        _ = tracker.setFollow(true, streamIsOpen: true)
        _ = tracker.setFollow(false, streamIsOpen: true)
        #expect(tracker.streamOpened() == nil)
    }

    @Test("A follow asked for with no stream open is sent when one opens")
    func followBeforeStreamOpens() {
        var tracker = FollowArchiveTracker()

        #expect(tracker.setFollow(true, streamIsOpen: false) == nil)
        #expect(tracker.wantsFollow)
        #expect(tracker.streamOpened() == .init(follow: true, seq: 1))
    }

    @Test("Reset forgets the wanted state")
    func resetForgets() {
        var tracker = FollowArchiveTracker()
        _ = tracker.streamOpened()
        _ = tracker.setFollow(true, streamIsOpen: true)

        tracker.reset()

        #expect(!tracker.wantsFollow)
        #expect(tracker.streamOpened() == nil)
    }
}
