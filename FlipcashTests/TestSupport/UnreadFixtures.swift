//
//  UnreadFixtures.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCore
import FlipcashStore
@testable import Flipcash

/// A controller over a real temp database with a viewer, a counterpart, and stored messages — shared
/// by the suites that read the viewer's unread state.
@MainActor
enum UnreadFixtures {

    static let me = UUID()
    static let them = UUID()

    static let base = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_000_000))
        .addingTimeInterval(9 * 60 * 60)

    static func message(_ id: UInt64, fromSelf: Bool, deleted: Bool = false, after offset: TimeInterval? = nil) -> ConversationMessage {
        let date = base.addingTimeInterval(offset ?? TimeInterval(id) * 60)
        return ConversationMessage(
            id: MessageID(value: id),
            senderID: fromSelf ? me : them,
            content: deleted ? .deleted(.init(deletedBy: them, deletedAt: date)) : .text("m\(id)"),
            date: date,
            unreadSeq: id
        )
    }

    /// A controller hydrated from a database holding `messages` and, when `pointer` is non-nil, the
    /// viewer's own member row reading through it. `hasConversationRow: false` stores the messages
    /// with no conversation, so a pointer advance lands only in the unsynced entry. `mock` is what
    /// the controller sends through.
    static func hydratedController(
        messages: [ConversationMessage],
        pointer: UInt64?,
        database: Database,
        hasConversationRow: Bool = true,
        mock: MockConversations = MockConversations()
    ) async throws -> ConversationController {
        var members = [ConversationMember(userID: them, displayName: "Them")]
        if let pointer {
            members.append(ConversationMember(userID: me, displayName: "", readPointer: MessageID(value: pointer)))
        }
        if hasConversationRow {
            try database.upsertConversation(
                Conversation(id: .test(1), members: members, lastMessage: nil, lastActivity: base)
            )
        }
        try database.upsertConversationMessages(messages, conversationID: .test(1))
        let controller = ConversationController(
            fetching: mock, membership: mock, viewerSettings: mock, messaging: mock, streaming: mock,
            contactNaming: MockDMContactNaming(),
            database: database,
            owner: .generate()!, selfUserID: me
        )
        await controller.hydrateFromDatabase()
        return controller
    }
}
