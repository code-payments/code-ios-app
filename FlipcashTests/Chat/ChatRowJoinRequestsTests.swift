//
//  ChatRowJoinRequestsTests.swift
//  FlipcashTests
//

import SwiftUI
import Testing
import FlipcashCore
import FlipcashUI
@testable import Flipcash

@MainActor
@Suite("Chat row join requests")
struct ChatRowJoinRequestsTests {

    private let preview = AttributedString("Erik: sounds good, I'll set it up tonight")

    /// Each run of `text` with its colour, so a test can read which part is which colour.
    private func runs(_ text: AttributedString?) -> [(String, Color?)] {
        guard let text else { return [] }
        return text.runs.map { (String(text[$0.range].characters), $0.foregroundColor) }
    }

    @Test("One requester is named; several are counted")
    func line() {
        #expect(ChatRowJoinRequests(requesterNames: []).line == nil)
        #expect(ChatRowJoinRequests(requesterNames: ["Jasper"]).line == "Jasper wants to join")
        #expect(ChatRowJoinRequests(requesterNames: [""]).line == "1 person wants to join")
        #expect(ChatRowJoinRequests(requesterNames: ["Jasper", "Ann", "Bo"]).line == "3 people want to join")
    }

    @Test("No requests leaves the preview as it was")
    func noRequests() {
        let subtitle = ChatRowJoinRequests(requesterNames: []).subtitle(preview: preview, hasUnreadMessages: true)
        #expect(subtitle == preview)
    }

    @Test("Requests without unread messages take the whole line in the unread colour")
    func requestsOnly() {
        let subtitle = ChatRowJoinRequests(requesterNames: ["Jasper"]).subtitle(preview: preview, hasUnreadMessages: false)
        let runs = runs(subtitle)
        #expect(runs.map(\.0) == ["Jasper wants to join"])
        #expect(runs.map(\.1) == [Color.unreadIndicator])
    }

    @Test("Requests with unread messages lead, then a dot and the preview in the secondary colour")
    func combined() {
        let subtitle = ChatRowJoinRequests(requesterNames: ["Jasper"]).subtitle(preview: preview, hasUnreadMessages: true)
        let runs = runs(subtitle)
        #expect(runs.map(\.0).joined() == "Jasper wants to join · Erik: sounds good, I'll set it up tonight")
        #expect(runs.map(\.0) == ["Jasper wants to join", " · Erik: sounds good, I'll set it up tonight"])
        #expect(runs.map(\.1) == [Color.unreadIndicator, Color.textSecondary])
    }

    @Test("Unread messages without a preview leave the request line alone")
    func combinedWithoutPreview() {
        let subtitle = ChatRowJoinRequests(requesterNames: ["Jasper"]).subtitle(preview: nil, hasUnreadMessages: true)
        #expect(runs(subtitle).map(\.0) == ["Jasper wants to join"])
    }

    @Test("The pill counts requests and unread messages together")
    func pillCount() {
        let one = ChatRowJoinRequests(requesterNames: ["Jasper"])
        #expect(one.pillCount(hasUnreadMessages: true, unreadMessageCount: 3) == 4)
        #expect(one.pillCount(hasUnreadMessages: false, unreadMessageCount: nil) == 1)
        #expect(ChatRowJoinRequests(requesterNames: ["A", "B", "C"]).pillCount(hasUnreadMessages: false, unreadMessageCount: nil) == 3)
    }

    @Test("An unknown message count leaves the pill a dot rather than a number that's too low")
    func pillUnknown() {
        #expect(ChatRowJoinRequests(requesterNames: ["Jasper"]).pillCount(hasUnreadMessages: true, unreadMessageCount: nil) == nil)
    }
}
