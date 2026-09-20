//
//  ChatDraftStore.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Observation
import FlipcashCore

/// Every chat's half-written message, held above the screen that was typing it.
///
/// Session-scoped rather than owned by the conversation's navigation destination, which is
/// destroyed by any pop — and disk-backed, because a background app killed under memory pressure
/// looks exactly like walking out and back to the person who typed the words.
///
/// Deliberately its own file rather than a table in `FlipcashStore`: that store's versioning is
/// destructive by design, and every other thing in it can be re-fetched from sync. A draft cannot.
/// Deliberately outside the App Group container too — the notification extensions have no use for
/// drafts, and staying out keeps them clear of `StoreLocation`'s move-and-version machinery.
@MainActor
@Observable
final class ChatDraftStore {

    /// A stored draft and when it was last written. `savedAt` is kept for a future draft indicator
    /// in the conversation list; nothing reads it yet.
    private struct Row: Codable {
        var draft: ChatDraft
        var savedAt: Date
    }

    private struct File: Codable {
        var version: Int
        var drafts: [String: Row]
    }

    private static let version = 1
    private static let fileName = "drafts.json"

    /// Long enough to keep a write off the keystroke path, short enough that an unclean kill
    /// between two keystrokes loses at most a word.
    private static let debounce = Duration.milliseconds(300)

    @ObservationIgnored private let url: URL
    @ObservationIgnored private var rows: [String: Row]
    @ObservationIgnored private var pendingWrite: Task<Void, Never>?

    /// Loads the session's drafts. A file that cannot be read is treated as no drafts: the words are
    /// gone either way, and refusing to start the session over them would be worse.
    init(directory: URL) {
        self.url = directory.appendingPathComponent(Self.fileName)
        guard
            let data = try? Data(contentsOf: url),
            let file = try? JSONDecoder().decode(File.self, from: data),
            file.version == Self.version
        else {
            self.rows = [:]
            return
        }
        self.rows = file.drafts
    }

    /// The draft held for a chat, or `nil` for one never typed in. An empty draft and no draft are
    /// different states, and this returns the difference.
    func draft(for conversationID: ConversationID) -> ChatDraft? {
        rows[Self.key(conversationID)]?.draft
    }

    /// Records what the composer is holding. A draft not worth keeping removes the row instead —
    /// the one place "empty means deleted" is implemented.
    func save(_ draft: ChatDraft, for conversationID: ConversationID) {
        guard draft.isWorthKeeping else {
            remove(for: conversationID)
            return
        }
        rows[Self.key(conversationID)] = Row(draft: draft, savedAt: .now)
        scheduleWrite()
    }

    /// Drops a chat's draft — sending it, leaving the chat, or blocking the person.
    func remove(for conversationID: ConversationID) {
        guard rows.removeValue(forKey: Self.key(conversationID)) != nil else { return }
        scheduleWrite()
    }

    /// Drops every draft, and the file with them. Logout and account switch, where leaving one
    /// account's half-written messages on disk for the next one would be the bug.
    func removeAll() {
        pendingWrite?.cancel()
        pendingWrite = nil
        rows = [:]
        try? FileManager.default.removeItem(at: url)
    }

    /// Writes now rather than on the debounce — the screen going away, and the app backgrounding,
    /// since neither guarantees a later callback runs before the process dies.
    func flush() {
        pendingWrite?.cancel()
        pendingWrite = nil
        write()
    }

    private func scheduleWrite() {
        pendingWrite?.cancel()
        pendingWrite = Task { [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled, let self else { return }
            self.pendingWrite = nil
            self.write()
        }
    }

    private func write() {
        do {
            let data = try JSONEncoder().encode(File(version: Self.version, drafts: rows))
            try data.write(to: url, options: .atomic)
        } catch {
            ErrorReporting.captureError(error, reason: "Failed to write chat drafts")
        }
    }

    /// Base64 of the id's own bytes rather than `base64URLEncoded`, whose decoder takes only the
    /// 32-byte DM shape — a group's id is 16 and would not survive the round trip.
    private static func key(_ conversationID: ConversationID) -> String {
        conversationID.data.base64EncodedString()
    }
}
