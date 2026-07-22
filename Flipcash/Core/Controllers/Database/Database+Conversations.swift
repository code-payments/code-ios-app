//
//  Database+Conversations.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCore
import SQLite

nonisolated extension Database {

    // MARK: - Get -

    /// Async wrapper that runs the synchronous cache reads off the caller's
    /// actor so session start never blocks the main thread on row decoding.
    func loadConversationCache() async throws -> (conversations: [Conversation], cursors: [ConversationID: UInt64]) {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let conversations = try self.getConversations()
                    let cursors = try self.getCatchupCursors()
                    continuation.resume(returning: (conversations, cursors))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// The persisted per-conversation event-log catch-up frontier (`GetDelta.after_sequence`), omitting
    /// conversations with no cursor yet.
    func getCatchupCursors() throws -> [ConversationID: UInt64] {
        let c = ConversationTable()
        let rows = try reader.prepareRowIterator(c.table).map { row in
            (id: ConversationID(data: row[c.id]), cursor: row[c.catchupCursor])
        }
        return rows.reduce(into: [:]) { result, row in
            if let cursor = row.cursor { result[row.id] = cursor }
        }
    }

    /// The persisted catch-up cursor for one conversation (0 when none) — used to re-seat the in-memory
    /// cursor after a failed message persist so recovery refetches, rather than skips, the window.
    func catchupCursor(conversationID: ConversationID) throws -> UInt64 {
        let c = ConversationTable()
        return (try reader.pluck(c.table.filter(c.id == conversationID.data))).flatMap { $0[c.catchupCursor] } ?? 0
    }

    /// The cached DM feed, most-recent activity first, with members and the
    /// newest stored message as the `lastMessage` preview.
    func getConversations() throws -> [Conversation] {
        let c = ConversationTable()
        let m = ConversationMemberTable()

        let memberRows = try reader.prepareRowIterator(m.table).map { row in
            (
                conversationId: row[m.conversationId],
                member: ConversationMember(
                    userID: row[m.userId],
                    displayName: row[m.displayName],
                    phoneE164: row[m.phoneE164],
                    readPointer: row[m.readPointer].map(MessageID.init(value:)),
                    readPointerTimestamp: row[m.readPointerTimestamp].map { Date(timeIntervalSinceReferenceDate: $0) },
                    profilePicture: memberProfilePicture(from: row)
                )
            )
        }
        var membersByConversation: [Data: [ConversationMember]] = [:]
        for row in memberRows {
            membersByConversation[row.conversationId, default: []].append(row.member)
        }

        let rows = try reader.prepareRowIterator(c.table.order(c.lastActivity.desc))
        return try rows.map { row in
            let id = row[c.id]
            return Conversation(
                id: ConversationID(data: id),
                members: membersByConversation[id] ?? [],
                lastMessage: try latestMessage(conversationId: id),
                lastActivity: Date(timeIntervalSinceReferenceDate: row[c.lastActivity]),
                type: ConversationType(rawValue: row[c.type]) ?? .contactDm
            )
        }
    }

    /// The newest stored non-deleted message for a conversation, or nil when none is cached. Tombstones
    /// (`kind == 2`) are skipped so the feed preview shows the newest *visible* message rather than a
    /// blank row for a deleted last message.
    func latestMessage(conversationID: ConversationID) throws -> ConversationMessage? {
        try latestMessage(conversationId: conversationID.data)
    }

    private func latestMessage(conversationId: Data) throws -> ConversationMessage? {
        let m = ConversationMessageTable()
        guard let row = try reader.pluck(
            m.table.filter(m.conversationId == conversationId && m.kind != 2).order(m.id.desc)
        ) else {
            return nil
        }
        return conversationMessage(from: row)
    }

    /// The newest stored message id (tombstones included) — the mark-read / receive-buzz anchor.
    func newestMessageID(conversationID: ConversationID) throws -> MessageID? {
        let m = ConversationMessageTable()
        return try reader.pluck(
            m.table.filter(m.conversationId == conversationID.data).order(m.id.desc)
        ).map { MessageID(value: $0[m.id]) }
    }

    /// The newest stored message (tombstones included). Unlike ``latestMessage(conversationID:)``, a
    /// delete of the newest message does not regress this value to the previous row — it returns the
    /// tombstone itself — so identity-keyed triggers (receive buzz, mark-read) don't misfire on deletes.
    func newestMessage(conversationID: ConversationID) throws -> ConversationMessage? {
        let m = ConversationMessageTable()
        guard let row = try reader.pluck(
            m.table.filter(m.conversationId == conversationID.data).order(m.id.desc)
        ) else {
            return nil
        }
        return conversationMessage(from: row)
    }

    /// Whether a specific message id is already persisted — the "is this a fresh echo?" gate for the
    /// optimistic-send reconcile, replacing the in-memory existence check.
    func messageExists(id: MessageID, conversationID: ConversationID) throws -> Bool {
        let m = ConversationMessageTable()
        return try reader.scalar(m.table.filter(m.conversationId == conversationID.data && m.id == id.value).count) > 0
    }

    /// All cached messages for a conversation, oldest first.
    func getConversationMessages(conversationID: ConversationID) throws -> [ConversationMessage] {
        let m = ConversationMessageTable()
        let rows = try reader.prepareRowIterator(
            m.table.filter(m.conversationId == conversationID.data).order(m.id.asc)
        )
        return try rows.map { conversationMessage(from: $0) }.compactMap { $0 }
    }

    /// A bounded window of a conversation's messages, oldest-first: the newest `limit` when `before` is
    /// nil, otherwise the `limit` messages immediately older than `before`. Index-backed by the
    /// composite `(conversationId, id)` primary key — no scan, no sort.
    func messagesWindow(conversationID: ConversationID, before: MessageID? = nil, limit: Int) throws -> [ConversationMessage] {
        let m = ConversationMessageTable()
        var query = m.table.filter(m.conversationId == conversationID.data)
        if let before {
            query = query.filter(m.id < before.value)
        }
        let rows = try reader.prepareRowIterator(query.order(m.id.desc).limit(limit))
        return Array(try rows.map { conversationMessage(from: $0) }.compactMap { $0 }.reversed())
    }

    /// Every message from `startID` (inclusive) to the newest, oldest-first — the id-anchored window.
    /// Anchoring by id means an arriving message grows the window at the tail instead of sliding the
    /// oldest revealed row out from under a reader who has scrolled up.
    func messages(conversationID: ConversationID, from startID: UInt64) throws -> [ConversationMessage] {
        let m = ConversationMessageTable()
        let rows = try reader.prepareRowIterator(
            m.table.filter(m.conversationId == conversationID.data && m.id >= startID).order(m.id.asc)
        )
        return try rows.map { conversationMessage(from: $0) }.compactMap { $0 }
    }

    /// The id `step` rows older than `before` — the next anchor when the reader pages back — falling
    /// back to the oldest available older row; nil when nothing older is persisted.
    func olderAnchor(conversationID: ConversationID, before: UInt64, step: Int) throws -> UInt64? {
        let m = ConversationMessageTable()
        let older = m.table.filter(m.conversationId == conversationID.data && m.id < before)
        if let row = try reader.pluck(older.order(m.id.desc).limit(1, offset: step - 1)) {
            return row[m.id]
        }
        return try reader.pluck(older.order(m.id.asc)).map { $0[m.id] }
    }

    /// The number of confirmed messages persisted for a conversation — the ceiling the transcript
    /// window can grow to before older history must be paged from the server.
    func messageCount(conversationID: ConversationID) throws -> Int {
        let m = ConversationMessageTable()
        return try reader.scalar(m.table.filter(m.conversationId == conversationID.data).count)
    }

    /// The oldest persisted message id for a conversation, or nil when none is cached — the anchor for
    /// paging genuinely older history from the server.
    func oldestMessageID(conversationID: ConversationID) throws -> MessageID? {
        let m = ConversationMessageTable()
        return try reader.pluck(
            m.table.filter(m.conversationId == conversationID.data).order(m.id.asc)
        ).map { MessageID(value: $0[m.id]) }
    }

    // MARK: - Write -

    /// Mirror one type's paged feed load: replaces that type's conversation + member sets (messages
    /// are retained, other types' conversations untouched), then stores each conversation's
    /// last-message preview.
    func replaceConversationFeed(_ conversations: [Conversation], type: ConversationType) throws {
        let c = ConversationTable()
        let m = ConversationMemberTable()
        let ids = conversations.map(\.id.data)
        try writer.transaction {
            // Delete only the same-type conversations that dropped out of this feed, then upsert the
            // rest. `writeConversation` upserts the row (leaving `catchupCursor` untouched on conflict)
            // and replaces that conversation's members, so a surviving conversation keeps its event-log
            // cursor without a read-and-restore dance.
            // Messages are deliberately NOT deleted here: they are the transcript's source of truth,
            // and a feed snapshot fetched before a brand-new chat's first message landed would
            // otherwise wipe that just-persisted message. Rows for conversations that genuinely left
            // the feed are orphaned but unread — nothing windows a conversation that isn't opened.
            let doomed = try writer.prepare(c.table.select(c.id).filter(c.type == type.rawValue && !ids.contains(c.id)))
                .map { $0[c.id] }
            if !doomed.isEmpty {
                try writer.run(c.table.filter(doomed.contains(c.id)).delete())
                try writer.run(m.table.filter(doomed.contains(m.conversationId)).delete())
            }
            for conversation in conversations where conversation.type == type {
                try writeConversation(conversation)
            }
        }
    }

    /// Advance the persisted catch-up cursor for a conversation without rewriting its members or
    /// last-message preview. No-ops for a conversation not yet in the feed.
    func updateCatchupCursor(_ value: UInt64, for conversationID: ConversationID) throws {
        let c = ConversationTable()
        try writer.run(c.table.filter(c.id == conversationID.data).update(c.catchupCursor <- value))
    }

    /// Upsert one conversation: its row, its members (replaced wholesale), and
    /// its last-message preview row.
    func upsertConversation(_ conversation: Conversation) throws {
        try writer.transaction {
            try writeConversation(conversation)
        }
    }

    /// Upsert messages for a conversation (insert-or-replace on the (conversation, id) key). History is
    /// retained — the transcript reads a bounded window from it, so there is no prune.
    func upsertConversationMessages(_ messages: [ConversationMessage], conversationID: ConversationID) throws {
        try writer.transaction {
            for message in messages {
                try writeMessage(message, conversationId: conversationID.data)
            }
        }
    }

    /// Atomically persist a batch and advance the catch-up cursor in one transaction, so a failed write
    /// can never leave the persisted cursor past a message that wasn't stored — which, once the DB is
    /// the working set, would orphan that message from GetDelta recovery. The cursor advances only when
    /// established (> 0) and only forward — a catch-up batch's interior checkpoint must not regress a
    /// cursor a live event already persisted. The conversation row need not exist yet (the update no-ops
    /// until it does).
    func persistMessages(_ messages: [ConversationMessage], cursor: UInt64, conversationID: ConversationID) throws {
        let c = ConversationTable()
        try writer.transaction {
            for message in messages {
                try writeMessage(message, conversationId: conversationID.data)
            }
            if cursor > 0 {
                let scoped = c.table.filter(c.id == conversationID.data)
                let current = try writer.pluck(scoped).flatMap { $0[c.catchupCursor] } ?? 0
                if cursor > current {
                    try writer.run(scoped.update(c.catchupCursor <- cursor))
                }
            }
        }
    }

    /// Deletes a conversation's persisted messages — used when a freshly fetched newest page does not
    /// overlap the retained history, so a stale older epoch can't render seamlessly stitched to the new
    /// page across an unfetchable gap.
    func deleteMessages(conversationID: ConversationID) throws {
        let m = ConversationMessageTable()
        try writer.run(m.table.filter(m.conversationId == conversationID.data).delete())
    }

    /// Must be called inside a `writer.transaction`.
    private func writeConversation(_ conversation: Conversation) throws {
        let c = ConversationTable()
        let m = ConversationMemberTable()

        try writer.run(
            c.table.upsert(
                c.id           <- conversation.id.data,
                c.lastActivity <- conversation.lastActivity.timeIntervalSinceReferenceDate,
                c.type         <- conversation.type.rawValue,
                onConflictOf: c.id
            )
        )

        try writer.run(m.table.filter(m.conversationId == conversation.id.data).delete())
        for member in conversation.members {
            try writer.run(
                m.table.insert(
                    m.conversationId        <- conversation.id.data,
                    m.userId                <- member.userID,
                    m.displayName           <- member.displayName,
                    m.phoneE164             <- member.phoneE164,
                    m.readPointer           <- member.readPointer?.value,
                    m.readPointerTimestamp  <- member.readPointerTimestamp?.timeIntervalSinceReferenceDate,
                    m.profilePictureBlobID          <- member.profilePicture?.blobID.data,
                    m.profilePictureThumbnailBlobID <- member.profilePicture?.thumbnailBlobID.data
                )
            )
        }

        if let lastMessage = conversation.lastMessage {
            try writeMessage(lastMessage, conversationId: conversation.id.data)
        }
    }

    /// Must be called inside a `writer.transaction`.
    private func writeMessage(_ message: ConversationMessage, conversationId: Data) throws {
        let m = ConversationMessageTable()

        let scoped = m.table.filter(m.conversationId == conversationId && m.id == message.id.value)
        var message = message

        // Last-writer-wins parity with the in-memory `ConversationStore`: never let a stale re-delivery
        // (e.g. the deprecated `new_messages` overlay landing after the `events` tombstone, or a
        // duplicate delta batch) overwrite a newer persisted version — that would resurrect a
        // deleted/pre-edit message across a relaunch, since the cache is what hydrates on cold boot.
        if let existing = try writer.pluck(scoped) {
            let existingSequence = existing[m.eventSequence]
            if existingSequence > message.eventSequence {
                return // stale re-delivery — keep the newer stored version
            }
            if existingSequence == message.eventSequence {
                // Equal version: keep the stored row, adopting only a client id it lacks (a reconcile
                // copy landing after a stream echo, or vice versa) so identity stays stable.
                if existing[m.clientMessageID] == nil, let clientMessageID = message.clientMessageID {
                    try writer.run(scoped.update(m.clientMessageID <- clientMessageID))
                }
                return
            }
            // Newer version wins; preserve the row's established identity if the newer copy lacks one.
            if message.clientMessageID == nil {
                message.clientMessageID = existing[m.clientMessageID]
            }
        }

        let kind: Int
        var text: String?
        var quarks: UInt64?
        var nativeAmount: String?
        var currency: CurrencyCode?
        var mint: PublicKey?

        switch message.content {
        case .text(let value):
            kind = 0
            text = value
        case .cash(let amount):
            kind = 1
            quarks = amount.onChainAmount.quarks
            nativeAmount = amount.nativeAmount.value.description
            currency = amount.nativeAmount.currency
            mint = amount.mint
        case .deleted:
            kind = 2
        }

        try writer.run(
            m.table.insert(
                or: .replace,
                m.conversationId <- conversationId,
                m.id             <- message.id.value,
                m.senderId       <- message.senderID,
                m.kind           <- kind,
                m.text           <- text,
                m.quarks         <- quarks,
                m.nativeAmount   <- nativeAmount,
                m.currency       <- currency,
                m.mint           <- mint,
                m.date           <- message.date.timeIntervalSinceReferenceDate,
                m.unreadSeq      <- message.unreadSeq,
                m.eventSequence  <- message.eventSequence,
                m.clientMessageID <- message.clientMessageID
            )
        )
    }

    // MARK: - Decode -

    /// Returns nil unless both rendition columns are present — the pair is
    /// written together, so a lone column is treated as no picture.
    private func memberProfilePicture(from row: RowIterator.Element) -> ProfilePicture? {
        let m = ConversationMemberTable()
        guard let blobID = row[m.profilePictureBlobID],
              let thumbnailBlobID = row[m.profilePictureThumbnailBlobID] else {
            return nil
        }
        return ProfilePicture(
            blobID: BlobID(data: blobID),
            thumbnailBlobID: BlobID(data: thumbnailBlobID)
        )
    }

    /// Returns nil for rows this client can't represent (unknown kind, a text
    /// row missing its text, or a cash row missing its amount columns).
    private func conversationMessage(from row: RowIterator.Element) -> ConversationMessage? {
        let m = ConversationMessageTable()

        let content: ConversationMessage.Content
        switch row[m.kind] {
        case 0:
            guard let text = row[m.text] else { return nil }
            content = .text(text)
        case 1:
            guard let quarks = row[m.quarks],
                  let nativeAmount = row[m.nativeAmount].flatMap({ Decimal(string: $0) }),
                  let currency = row[m.currency],
                  let mint = row[m.mint] else {
                return nil
            }
            let onChain = TokenAmount(quarks: quarks, mint: mint)
            let native = FiatAmount(value: nativeAmount, currency: currency)
            // Synthesize the FX rate from the stored amounts, mirroring the
            // activity table's ExchangedFiat decomposition.
            let fx: Decimal = onChain.decimalValue > 0
                ? native.value / onChain.decimalValue
                : 1
            content = .cash(ExchangedFiat(
                onChainAmount: onChain,
                nativeAmount: native,
                currencyRate: Rate(fx: fx, currency: currency)
            ))
        case 2:
            content = .deleted
        default:
            return nil
        }

        return ConversationMessage(
            id: MessageID(value: row[m.id]),
            senderID: row[m.senderId],
            content: content,
            date: Date(timeIntervalSinceReferenceDate: row[m.date]),
            unreadSeq: row[m.unreadSeq],
            eventSequence: row[m.eventSequence],
            clientMessageID: row[m.clientMessageID]
        )
    }
}
