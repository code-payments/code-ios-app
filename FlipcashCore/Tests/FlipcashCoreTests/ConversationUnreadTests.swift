//
//  ConversationUnreadTests.swift
//  FlipcashCoreTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
@testable import FlipcashCore

@Suite("Conversation unread state")
struct ConversationUnreadTests {

    private let selfID = UUID()
    private let otherID = UUID()

    private func conversation(
        lastMessageID: UInt64?,
        readPointer: UInt64?,
        otherReadPointer: UInt64? = nil
    ) -> Conversation {
        Conversation(
            id: ConversationID(data: Data(repeating: 0x01, count: 32)),
            members: [
                ConversationMember(
                    userID: selfID,
                    displayName: "Self",
                    readPointer: readPointer.map(MessageID.init(value:))
                ),
                ConversationMember(
                    userID: otherID,
                    displayName: "Them",
                    readPointer: otherReadPointer.map(MessageID.init(value:))
                ),
            ],
            lastMessage: lastMessageID.map { id in
                ConversationMessage(
                    id: MessageID(value: id),
                    senderID: otherID,
                    content: .text("hello"),
                    date: .now,
                    unreadSeq: id
                )
            },
            lastActivity: .now
        )
    }

    @Test("No messages is never unread")
    func emptyConversationIsRead() {
        let conversation = conversation(lastMessageID: nil, readPointer: nil)
        #expect(conversation.hasUnread(for: selfID) == false)
    }

    @Test("A message with no READ watermark is unread")
    func missingPointerIsUnread() {
        let conversation = conversation(lastMessageID: 1, readPointer: nil)
        #expect(conversation.hasUnread(for: selfID) == true)
    }

    @Test("A message past the READ watermark is unread")
    func newerMessageIsUnread() {
        let conversation = conversation(lastMessageID: 5, readPointer: 4)
        #expect(conversation.hasUnread(for: selfID) == true)
    }

    @Test("A message at the READ watermark is read")
    func watermarkMessageIsRead() {
        let conversation = conversation(lastMessageID: 5, readPointer: 5)
        #expect(conversation.hasUnread(for: selfID) == false)
    }

    @Test("A watermark past the last message is read")
    func aheadWatermarkIsRead() {
        let conversation = conversation(lastMessageID: 5, readPointer: 9)
        #expect(conversation.hasUnread(for: selfID) == false)
    }

    @Test("The counterpart's watermark doesn't count for the signed-in user")
    func otherMembersPointerIsIgnored() {
        let conversation = conversation(lastMessageID: 5, readPointer: nil, otherReadPointer: 5)
        #expect(conversation.hasUnread(for: selfID) == true)
    }

    /// One row of the unread table shared with Android's `FeedProjection.unreadCount`.
    struct UnreadCase: Sendable, CustomTestStringConvertible {
        let newest: UInt64?
        let fromSelf: Bool
        let hasSelfRow: Bool
        let pointer: UInt64?
        let type: ConversationType
        let unread: Bool

        var testDescription: String {
            let newest = newest.map { "\($0)" } ?? "none"
            let pointer = pointer.map { "\($0)" } ?? "—"
            return "newest \(newest) from \(fromSelf ? "self" : "other"), self row \(hasSelfRow ? "yes" : "no"), pointer \(pointer), \(type) → \(unread ? "unread" : "read")"
        }
    }

    static let unreadTable: [UnreadCase] = [
        UnreadCase(newest: 5, fromSelf: false, hasSelfRow: true, pointer: 4, type: .contactDm, unread: true),
        UnreadCase(newest: 5, fromSelf: true, hasSelfRow: true, pointer: 4, type: .contactDm, unread: false),
        UnreadCase(newest: 5, fromSelf: false, hasSelfRow: true, pointer: 5, type: .group, unread: false),
        UnreadCase(newest: 5, fromSelf: false, hasSelfRow: false, pointer: nil, type: .group, unread: false),
        UnreadCase(newest: 5, fromSelf: false, hasSelfRow: false, pointer: nil, type: .contactDm, unread: true),
        UnreadCase(newest: nil, fromSelf: false, hasSelfRow: true, pointer: 4, type: .contactDm, unread: false),
    ]

    @Test("Unread follows the newest message's sender, the self row, and the chat type", arguments: unreadTable)
    func unreadTableCase(_ row: UnreadCase) {
        var members = [ConversationMember(userID: otherID, displayName: "Them")]
        if row.hasSelfRow {
            members.insert(ConversationMember(userID: selfID, displayName: "Self", readPointer: row.pointer.map(MessageID.init(value:))), at: 0)
        }
        let conversation = Conversation(
            id: ConversationID(data: Data(repeating: 0x01, count: 32)),
            members: members,
            lastMessage: row.newest.map { id in
                ConversationMessage(
                    id: MessageID(value: id),
                    senderID: row.fromSelf ? selfID : otherID,
                    content: .text("hello"),
                    date: .now,
                    unreadSeq: id
                )
            },
            lastActivity: .now,
            type: row.type
        )
        #expect(conversation.hasUnread(for: selfID) == row.unread)
    }

    // MARK: - Unread count -

    /// A chat whose newest message is `lastSeq` on the unread sequence, with the viewer's READ
    /// watermark at message `readPointer`.
    private func counted(lastID: UInt64, lastSeq: UInt64, readPointer: UInt64?, fromSelf: Bool = false) -> Conversation {
        Conversation(
            id: ConversationID(data: Data(repeating: 0x01, count: 32)),
            members: [
                ConversationMember(userID: selfID, displayName: "Self", readPointer: readPointer.map(MessageID.init(value:))),
                ConversationMember(userID: otherID, displayName: "Them"),
            ],
            lastMessage: ConversationMessage(
                id: MessageID(value: lastID),
                senderID: fromSelf ? selfID : otherID,
                content: .text("hello"),
                date: .now,
                unreadSeq: lastSeq
            ),
            lastActivity: .now
        )
    }

    @Test("The count is the newest stamp less the stamp at the watermark")
    func countSubtractsWatermarkStamp() {
        // Message 20 carries stamp 12; the watermark's message 8 carried stamp 5.
        let conversation = counted(lastID: 20, lastSeq: 12, readPointer: 8)
        #expect(conversation.unreadCount(for: selfID) { $0.value == 8 ? 5 : nil } == 7)
    }

    @Test("A DM with no watermark counts every unread-eligible message")
    func missingPointerCountsFromZero() {
        let conversation = counted(lastID: 20, lastSeq: 15, readPointer: nil)
        #expect(conversation.unreadCount(for: selfID) { _ in nil } == 15)
    }

    @Test("A watermark whose message isn't stored leaves the count unknown")
    func unstoredWatermarkIsUnknown() {
        let conversation = counted(lastID: 20, lastSeq: 12, readPointer: 8)
        #expect(conversation.unreadCount(for: selfID) { _ in nil } == nil)
    }

    @Test("A read chat counts zero without looking up the watermark")
    func readChatIsZero() {
        let conversation = counted(lastID: 8, lastSeq: 5, readPointer: 8)
        #expect(conversation.unreadCount(for: selfID) { _ in Issue.record("looked up"); return nil } == 0)
    }

    @Test("The viewer's own newest message counts zero")
    func ownMessageIsZero() {
        let conversation = counted(lastID: 20, lastSeq: 12, readPointer: 8, fromSelf: true)
        #expect(conversation.unreadCount(for: selfID) { _ in 5 } == 0)
    }

    @Test("Unread by id but not by stamp leaves the count unknown")
    func ineligibleNewestIsUnknown() {
        // The newest message didn't advance the stamp past the watermark's.
        let conversation = counted(lastID: 20, lastSeq: 5, readPointer: 8)
        #expect(conversation.unreadCount(for: selfID) { _ in 5 } == nil)
    }
}
