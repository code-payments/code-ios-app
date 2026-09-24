//
//  ReadWatermarkStamps.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCore

/// The `unreadSeq` of READ-watermark messages the device doesn't store, fetched one message at a
/// time so a chat row can show an exact unread count. Owns the fetched stamps, the fetches in
/// flight, and the watermarks the server has no message for, as one unit.
///
/// Held in memory only: a stamp never changes once the server assigns it, and keeping these out of
/// the message table keeps a lone fetched message from reading as part of a transcript.
@MainActor @Observable
final class ReadWatermarkStamps {

    /// A watermark: the message a chat's READ pointer names.
    struct Key: Hashable {
        let conversationID: ConversationID
        let messageID: MessageID
    }

    private var stamps: [Key: UInt64] = [:]
    @ObservationIgnored private var inFlight: Set<Key> = []
    @ObservationIgnored private var missing: Set<Key> = []

    /// The fetched stamp for `key`, or nil when it hasn't been fetched.
    func stamp(for key: Key) -> UInt64? {
        stamps[key]
    }

    /// Fetches `key`'s message unless it's already stamped, in flight, or known missing. A failed
    /// fetch leaves the key unresolved, so the next call tries again.
    func resolve(_ key: Key, fetch: () async throws -> ConversationMessage?) async throws {
        guard stamps[key] == nil, !inFlight.contains(key), !missing.contains(key) else { return }
        inFlight.insert(key)
        defer { inFlight.remove(key) }
        if let message = try await fetch() {
            stamps[key] = message.unreadSeq
        } else {
            missing.insert(key)
        }
    }
}
