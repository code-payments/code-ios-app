//
//  Regression_6a510fab7372e33c88417bd4.swift
//  FlipcashTests
//
//  "Chat delta catch-up failed: denied" — during a push deeplink,
//  ConversationScreen.onAppear briefly set visibleConversationID to the pushed
//  contact snapshot's stale dmChatID before onChange corrected it to the
//  directory-resolved id. The scenePhase-active hook captured the transient and
//  spent a GetDelta on a conversation the user has no membership in; the
//  server denied it.
//
//  Fix: ConversationController.catchUp no-ops for a conversation the client
//  holds nothing for — absent from the store, no messages, no applied cursor —
//  so no trigger (foreground, reconnect, live gap) can spend a GetDelta on a
//  transient id.
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("Regression: 6a510fa – GetDelta spent on a non-materialized conversation", .bug("6a510fab7372e33c88417bd4"))
struct Regression_6a510fa {

    private func makeController(_ mock: MockConversations) -> ConversationController {
        ConversationController(
            fetching: mock, messaging: mock, streaming: mock,
            contactNaming: MockDMContactNaming(),
            database: try! Database.makeTemp().database,
            owner: .generate()!, selfUserID: UUID()
        )
    }

    @Test("catch-up no-ops for a conversation the client holds nothing for")
    func catchUp_unmaterializedConversation_skipsGetDelta() async {
        let mock = MockConversations()
        let controller = makeController(mock)

        await controller.catchUp(conversationID: .test(99))

        #expect(mock.deltaAfterSequences.isEmpty)
    }

    @Test("catch-up still reconciles a conversation present in the feed, even with no cursor")
    func catchUp_feedConversationWithoutCursor_runsGetDelta() async {
        let mock = MockConversations()
        mock.feed = [Conversation(id: .test(1), members: [], lastMessage: nil, lastActivity: Date(timeIntervalSince1970: 100))]
        let controller = makeController(mock)
        await controller.loadFeed()

        await controller.catchUp(conversationID: .test(1))

        #expect(mock.deltaAfterSequences == [0])
    }
}
