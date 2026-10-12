//
//  ChatListFilterTests.swift
//  FlipcashTests
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("Chat list filter")
struct ChatListFilterTests {

    private func projection() -> ChatListProjection<Int> {
        ChatListProjection.project([
            ChatListEntry(id: 1, type: .tipDm, lastActivity: Date(timeIntervalSince1970: 3), isArchived: false, isMuted: false, isHidden: false, unread: .count(2)),
            ChatListEntry(id: 2, type: .group, lastActivity: Date(timeIntervalSince1970: 2), isArchived: false, isMuted: false, isHidden: false, unread: .count(0)),
            ChatListEntry(id: 3, type: .group, lastActivity: Date(timeIntervalSince1970: 1), isArchived: false, isMuted: false, isHidden: false, unread: .unknown),
        ])
    }

    @Test("Each filter picks its projection's ids")
    func ids() {
        let p = projection()
        #expect(ChatListFilter.all.ids(in: p) == [1, 2, 3])
        #expect(ChatListFilter.unread.ids(in: p) == [1, 3])
        #expect(ChatListFilter.groups.ids(in: p) == [2, 3])
    }

    @Test("All shows no count; Unread and Groups show unread counts, hiding zero")
    func counts() {
        let p = projection()
        #expect(ChatListFilter.all.badge(in: p) == nil)
        #expect(ChatListFilter.unread.badge(in: p) == 2)
        #expect(ChatListFilter.groups.badge(in: p) == 1)
    }

    @Test("A zero count is no badge")
    func zeroIsNil() {
        let p = ChatListProjection<Int>.project([])
        #expect(ChatListFilter.unread.badge(in: p) == nil)
    }
}
