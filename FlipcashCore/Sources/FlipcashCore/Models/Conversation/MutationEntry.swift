//
//  MutationEntry.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// An edit or delete that has been issued but not yet confirmed, overlaid on the stored message so
/// the transcript reflects it immediately. The mirror image of `PendingEntry`, which does the same
/// job for a message that has not been sent yet.
public struct MutationEntry: Hashable, Sendable {

    public enum Kind: Hashable, Sendable {
        case edited(String)
        case deleted
    }

    public let messageID: MessageID
    public let kind: Kind
    /// The `eventSequence` the message carried when the mutation was issued — the same value sent as
    /// `expected_event_sequence`. A stored row that exceeds it is the server's newer answer, and the
    /// overlay stops applying.
    public let expectedSequence: UInt64

    public init(messageID: MessageID, kind: Kind, expectedSequence: UInt64) {
        self.messageID = messageID
        self.kind = kind
        self.expectedSequence = expectedSequence
    }
}
