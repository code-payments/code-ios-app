//
//  FollowArchiveTracker.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// The `FollowArchive` requests sent on the event stream, and which ack settles them.
///
/// A user stream carries archived groups' updates only while the client follows the archive. The
/// client sends `FollowArchive(follow, seq)` whenever that changes, and the server answers each with
/// `FollowArchiveAck(seq)`, in order. A seq numbers the requests of one stream, so it restarts with
/// every stream, and only the ack for the latest request counts: an ack for an earlier one answers a
/// state the client has already moved past.
///
/// What the client wants outlives a stream. A reconnect while the client follows sends
/// `FollowArchive(true)` again, right after `Params`, and its ack is the moment to re-read the
/// archived groups the drop may have hidden.
struct FollowArchiveTracker: Equatable, Sendable {

    /// A request to send on the stream.
    struct Request: Equatable, Sendable {
        let follow: Bool
        let seq: UInt64
    }

    /// What an ack means for the caller.
    enum Ack: Equatable, Sendable {
        /// The server now carries archived groups' updates on this stream. Re-read them, since any
        /// update before this point went unsent.
        case following
        /// The server stopped carrying them.
        case notFollowing
        /// An ack for a request the client has since replaced, or one it already counted. Ignore it.
        case stale
    }

    /// Whether the client wants archived groups' updates. Kept across streams.
    private(set) var wantsFollow = false

    /// The latest request sent on the current stream, `nil` before the first.
    private(set) var latest: Request?

    /// The seq of the latest ack counted on the current stream, so a repeat counts once.
    private var acknowledgedSeq: UInt64 = 0

    /// Restarts the seq for a stream that just opened. Returns the request to send right after
    /// `Params`, or `nil` when the client does not follow: the server starts every stream unfollowed.
    mutating func streamOpened() -> Request? {
        latest = nil
        acknowledgedSeq = 0
        guard wantsFollow else { return nil }
        return makeRequest(follow: true)
    }

    /// Records what the client wants. Returns the request to send, or `nil` when nothing changed or
    /// no stream is open; ``streamOpened()`` sends it once one is.
    mutating func setFollow(_ follow: Bool, streamIsOpen: Bool) -> Request? {
        guard follow != wantsFollow else { return nil }
        wantsFollow = follow
        guard streamIsOpen else { return nil }
        return makeRequest(follow: follow)
    }

    /// Classifies an ack received on the current stream.
    mutating func acknowledge(seq: UInt64) -> Ack {
        guard let latest, seq == latest.seq, seq > acknowledgedSeq else { return .stale }
        acknowledgedSeq = seq
        return latest.follow ? .following : .notFollowing
    }

    /// Forgets everything, for a stopped stream: the next session starts unfollowed.
    mutating func reset() {
        self = FollowArchiveTracker()
    }

    private mutating func makeRequest(follow: Bool) -> Request {
        let request = Request(follow: follow, seq: (latest?.seq ?? 0) + 1)
        latest = request
        return request
    }
}
