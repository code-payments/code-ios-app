//
//  ChatListSelectionTests.swift
//  FlipcashCoreTests
//

import Foundation
import Testing
@testable import FlipcashCore

@Suite("Chat list selection")
struct ChatListSelectionTests {

    private static func conversation(_ byte: UInt8, type: ConversationType, activity: TimeInterval = 0, hidden: Bool = false) -> Conversation {
        Conversation(
            id: ConversationID(data: Data(repeating: byte, count: 32)),
            members: [],
            lastMessage: nil,
            lastActivity: Date(timeIntervalSinceReferenceDate: activity),
            type: type,
            isHidden: hidden
        )
    }

    @Test("Source keeps tip DMs and joined groups, tip DMs first")
    func source() {
        let group = Self.conversation(1, type: .group)
        let tip = Self.conversation(2, type: .tipDm)
        let contact = Self.conversation(3, type: .contactDm)
        let unjoined = Self.conversation(4, type: .group)
        let hidden = Self.conversation(5, type: .tipDm, hidden: true)

        let result = ChatListSelection.source(from: [group, tip, contact, unjoined, hidden], isMember: { $0.id == group.id })

        #expect(result.map(\.id) == [tip.id, group.id])
    }

    @Test("Main list matches the projection's order and drops archived chats")
    func mainList() {
        let a = Self.conversation(1, type: .tipDm, activity: 10)
        let b = Self.conversation(2, type: .group, activity: 30)
        let c = Self.conversation(3, type: .tipDm, activity: 20)
        let archived = Self.conversation(4, type: .tipDm, activity: 99)

        let result = ChatListSelection.mainList(from: [a, b, c, archived], joinedGroupIDs: [b.id], archivedIDs: [archived.id])

        #expect(result.map(\.id) == [b.id, c.id, a.id])
    }

    @Test("Equal activity keeps source order")
    func tiebreak() {
        let tip = Self.conversation(1, type: .tipDm, activity: 5)
        let group = Self.conversation(2, type: .group, activity: 5)

        let result = ChatListSelection.mainList(from: [group, tip], joinedGroupIDs: [group.id], archivedIDs: [])

        #expect(result.map(\.id) == [tip.id, group.id])
    }
}
