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
    func loadConversationCache() async throws -> (conversations: [Conversation], messages: [ConversationID: [ConversationMessage]], cursors: [ConversationID: UInt64]) {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let conversations = try self.getConversations()
                    var messages: [ConversationID: [ConversationMessage]] = [:]
                    for conversation in conversations {
                        messages[conversation.id] = try self.getConversationMessages(conversationID: conversation.id)
                    }
                    let cursors = try self.getCatchupCursors()
                    continuation.resume(returning: (conversations, messages, cursors))
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
                    readPointerTimestamp: row[m.readPointerTimestamp].map { Date(timeIntervalSinceReferenceDate: $0) }
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
                lastActivity: Date(timeIntervalSinceReferenceDate: row[c.lastActivity])
            )
        }
    }

    /// The newest stored non-deleted message for a conversation, or nil when none is cached. Tombstones
    /// (`kind == 2`) are skipped so the feed preview shows the newest *visible* message rather than a
    /// blank row for a deleted last message.
    private func latestMessage(conversationId: Data) throws -> ConversationMessage? {
        let m = ConversationMessageTable()
        guard let row = try reader.pluck(
            m.table.filter(m.conversationId == conversationId && m.kind != 2).order(m.id.desc)
        ) else {
            return nil
        }
        return conversationMessage(from: row)
    }

    /// All cached messages for a conversation, oldest first.
    func getConversationMessages(conversationID: ConversationID) throws -> [ConversationMessage] {
        let m = ConversationMessageTable()
        let rows = try reader.prepareRowIterator(
            m.table.filter(m.conversationId == conversationID.data).order(m.id.asc)
        )
        return try rows.map { conversationMessage(from: $0) }.compactMap { $0 }
    }

    // MARK: - Write -

    /// Mirror a paged feed load: replaces the conversation + member sets and
    /// prunes messages of conversations no longer in the feed, then stores
    /// each conversation's last-message preview.
    func replaceConversationFeed(_ conversations: [Conversation]) throws {
        let c = ConversationTable()
        let m = ConversationMemberTable()
        let msg = ConversationMessageTable()
        let ids = conversations.map(\.id.data)
        try writer.transaction {
            // Delete only the conversations that dropped out of the feed, then upsert the rest.
            // `writeConversation` upserts the row (leaving `catchupCursor` untouched on conflict) and
            // replaces that conversation's members, so a surviving conversation keeps its event-log
            // cursor without a read-and-restore dance.
            if ids.isEmpty {
                try writer.run(c.table.delete())
                try writer.run(m.table.delete())
                try writer.run(msg.table.delete())
            } else {
                try writer.run(c.table.filter(!ids.contains(c.id)).delete())
                try writer.run(m.table.filter(!ids.contains(m.conversationId)).delete())
                try writer.run(msg.table.filter(!ids.contains(msg.conversationId)).delete())
            }
            for conversation in conversations {
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

    /// Newest messages kept per conversation. The slack is hysteresis: pruning
    /// only fires once a conversation exceeds the window by this much, so
    /// steady-state single-message writes don't pay a prune each time.
    static let messageWindow = 100
    static let messageWindowSlack = 20

    /// Upsert messages for a conversation (insert-or-replace on the
    /// (conversation, id) key), then prune anything older than the window.
    func upsertConversationMessages(_ messages: [ConversationMessage], conversationID: ConversationID) throws {
        try writer.transaction {
            for message in messages {
                try writeMessage(message, conversationId: conversationID.data)
            }
            try pruneMessages(conversationId: conversationID.data)
        }
    }

    /// Deletes all but the newest ``messageWindow`` rows once the count exceeds
    /// the window plus ``messageWindowSlack``. Must be called inside a
    /// `writer.transaction`.
    private func pruneMessages(conversationId: Data) throws {
        let m = ConversationMessageTable()
        let scoped = m.table.filter(m.conversationId == conversationId)
        guard try writer.scalar(scoped.count) > Self.messageWindow + Self.messageWindowSlack else { return }
        guard let cutoff = try writer.pluck(
            scoped.order(m.id.desc).limit(1, offset: Self.messageWindow - 1)
        ) else { return }
        try writer.run(scoped.filter(m.id < cutoff[m.id]).delete())
    }

    /// Must be called inside a `writer.transaction`.
    private func writeConversation(_ conversation: Conversation) throws {
        let c = ConversationTable()
        let m = ConversationMemberTable()

        try writer.run(
            c.table.upsert(
                c.id           <- conversation.id.data,
                c.lastActivity <- conversation.lastActivity.timeIntervalSinceReferenceDate,
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
                    m.readPointerTimestamp  <- member.readPointerTimestamp?.timeIntervalSinceReferenceDate
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

        // Last-writer-wins parity with the in-memory `ConversationStore`: never let a stale re-delivery
        // (e.g. the deprecated `new_messages` overlay landing after the `events` tombstone, or a
        // duplicate delta batch) overwrite a newer persisted version — that would resurrect a
        // deleted/pre-edit message across a relaunch, since the cache is what hydrates on cold boot.
        if let existing = try writer.pluck(m.table.filter(m.conversationId == conversationId && m.id == message.id.value)),
           existing[m.eventSequence] > message.eventSequence {
            return
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
                m.eventSequence  <- message.eventSequence
            )
        )
    }

    // MARK: - Decode -

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
            eventSequence: row[m.eventSequence]
        )
    }
}
