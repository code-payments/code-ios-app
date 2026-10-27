//
//  ChatListJoinRequestsTests.swift
//  FlipcashCoreTests
//

import Foundation
import Testing
@testable import FlipcashCore

@Suite("Chat list join requests")
struct ChatListJoinRequestsTests {

    private static func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    private static func entry(
        _ id: Int,
        type: ConversationType = .group,
        activity: TimeInterval,
        archived: Bool = false,
        muted: Bool = false,
        unread: ChatListUnread = .count(0),
        requests: Int = 0,
        newestRequest: TimeInterval? = nil
    ) -> ChatListEntry<Int> {
        ChatListEntry(
            id: id,
            type: type,
            lastActivity: date(activity),
            isArchived: archived,
            isMuted: muted,
            isHidden: false,
            unread: unread,
            joinRequests: requests == 0 ? .none : ChatListJoinRequests(count: requests, newestEnteredAt: newestRequest.map(date))
        )
    }

    @Test("Sort time is the later of last activity and the newest request")
    func sortTime() {
        let requests = ChatListJoinRequests(count: 2, newestEnteredAt: Self.date(50))
        #expect(requests.sortTime(after: Self.date(10)) == Self.date(50))
        #expect(requests.sortTime(after: Self.date(90)) == Self.date(90))
        #expect(ChatListJoinRequests.none.sortTime(after: Self.date(10)) == Self.date(10))
        #expect(ChatListJoinRequests(count: 1, newestEnteredAt: nil).sortTime(after: Self.date(10)) == Self.date(10))
    }

    @Test("A new request moves its group above chats with older activity, not newer")
    func ordersBySortTime() {
        let p = ChatListProjection.project([
            Self.entry(1, type: .tipDm, activity: 40),
            Self.entry(2, activity: 10, requests: 1, newestRequest: 30),
            Self.entry(3, type: .tipDm, activity: 20),
            Self.entry(4, type: .tipDm, activity: 50),
        ])
        #expect(p.main == [4, 1, 2, 3])
    }

    @Test("A group with only requests is unread for the chip, the filters and the tab badge")
    func requestsCountAsUnread() {
        let p = ChatListProjection.project([
            Self.entry(1, activity: 30, requests: 2, newestRequest: 30),
            Self.entry(2, activity: 20),
            Self.entry(3, type: .tipDm, activity: 10, unread: .count(4)),
        ])
        #expect(p.unreadChip == [1, 3])
        #expect(p.unreadChipCount == 2)
        #expect(p.groupsChip == [1, 2])
        #expect(p.groupsChipCount == 1)
        #expect(p.tabBadge == 2)
    }

    @Test("A group with requests and unread messages counts once, as one chat")
    func requestsAndMessagesCountOnce() {
        let p = ChatListProjection.project([
            Self.entry(1, activity: 30, unread: .count(3), requests: 1, newestRequest: 20),
        ])
        #expect(p.unreadChipCount == 1)
        #expect(p.tabBadge == 1)
    }

    @Test("An archived hosted group stays archived and its requests count on the Archived row")
    func archivedRequests() {
        let p = ChatListProjection.project([
            Self.entry(1, activity: 50, archived: true, requests: 1, newestRequest: 60),
            Self.entry(2, activity: 40, archived: true),
            Self.entry(3, type: .tipDm, activity: 10),
        ])
        #expect(p.main == [3])
        #expect(p.archived == [1, 2])
        #expect(p.archivedRowCount == 1)
        #expect(p.tabBadge == 0)
    }

    @Test("A muted archived group's requests leave the Archived row's count alone, as its messages do")
    func mutedArchivedRequests() {
        let p = ChatListProjection.project([
            Self.entry(1, activity: 50, archived: true, muted: true, requests: 1, newestRequest: 60),
        ])
        #expect(p.archivedRowCount == 0)
    }
}
