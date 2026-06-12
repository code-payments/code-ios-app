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
                    readPointer: row[m.readPointer].map(MessageID.init(value:))
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
                lastActivity: row[c.lastActivity]
            )
        }
    }

    /// All cached messages for a conversation, oldest first.
    func getConversationMessages(conversationID: ConversationID) throws -> [ConversationMessage] {
        let m = ConversationMessageTable()
        let rows = try reader.prepareRowIterator(
            m.table.filter(m.conversationId == conversationID.data).order(m.id.asc)
        )
        return try rows.map { conversationMessage(from: $0) }.compactMap { $0 }
    }

    private func latestMessage(conversationId: Data) throws -> ConversationMessage? {
        let m = ConversationMessageTable()
        guard let row = try reader.pluck(
            m.table.filter(m.conversationId == conversationId).order(m.id.desc)
        ) else {
            return nil
        }
        return conversationMessage(from: row)
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
            try writer.run(c.table.delete())
            try writer.run(m.table.delete())
            if ids.isEmpty {
                try writer.run(msg.table.delete())
            } else {
                try writer.run(msg.table.filter(!ids.contains(msg.conversationId)).delete())
            }
            for conversation in conversations {
                try writeConversation(conversation)
            }
        }
    }

    /// Upsert one conversation: its row, its members (replaced wholesale), and
    /// its last-message preview row.
    func upsertConversation(_ conversation: Conversation) throws {
        try writer.transaction {
            try writeConversation(conversation)
        }
    }

    /// Upsert messages for a conversation (insert-or-replace on the
    /// (conversation, id) key).
    func upsertConversationMessages(_ messages: [ConversationMessage], conversationID: ConversationID) throws {
        try writer.transaction {
            for message in messages {
                try writeMessage(message, conversationId: conversationID.data)
            }
        }
    }

    /// Must be called inside a `writer.transaction`.
    private func writeConversation(_ conversation: Conversation) throws {
        let c = ConversationTable()
        let m = ConversationMemberTable()

        try writer.run(
            c.table.upsert(
                c.id           <- conversation.id.data,
                c.lastActivity <- conversation.lastActivity,
                onConflictOf: c.id
            )
        )

        try writer.run(m.table.filter(m.conversationId == conversation.id.data).delete())
        for member in conversation.members {
            try writer.run(
                m.table.insert(
                    m.conversationId <- conversation.id.data,
                    m.userId         <- member.userID,
                    m.displayName    <- member.displayName,
                    m.readPointer    <- member.readPointer?.value
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

        let kind: Int
        var text: String?
        var quarks: UInt64?
        var nativeAmount: Double?
        var currency: CurrencyCode?
        var mint: PublicKey?

        switch message.content {
        case .text(let value):
            kind = 0
            text = value
        case .cash(let amount):
            kind = 1
            quarks = amount.onChainAmount.quarks
            nativeAmount = amount.nativeAmount.doubleValue
            currency = amount.nativeAmount.currency
            mint = amount.mint
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
                m.date           <- message.date,
                m.unreadSeq      <- message.unreadSeq
            )
        )
    }

    // MARK: - Decode -

    /// Returns nil for rows this client can't represent (unknown kind, or a
    /// cash row missing its amount columns).
    private func conversationMessage(from row: RowIterator.Element) -> ConversationMessage? {
        let m = ConversationMessageTable()

        let content: ConversationMessage.Content
        switch row[m.kind] {
        case 0:
            content = .text(row[m.text] ?? "")
        case 1:
            guard let quarks = row[m.quarks],
                  let nativeAmount = row[m.nativeAmount],
                  let currency = row[m.currency],
                  let mint = row[m.mint] else {
                return nil
            }
            let onChain = TokenAmount(quarks: quarks, mint: mint)
            let native = FiatAmount(value: Decimal(nativeAmount), currency: currency)
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
        default:
            return nil
        }

        return ConversationMessage(
            id: MessageID(value: row[m.id]),
            senderID: row[m.senderId],
            content: content,
            date: row[m.date],
            unreadSeq: row[m.unreadSeq]
        )
    }
}
