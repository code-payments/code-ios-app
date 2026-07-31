//
//  ConversationHiddenTests.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
@testable import FlipcashCore

@Suite("Conversation isHidden")
struct ConversationHiddenTests {

    private func convo(_ id: UInt8, hidden: Bool) -> Conversation {
        Conversation(
            id: ConversationID(data: Data(repeating: id, count: 32)),
            members: [],
            lastMessage: nil,
            lastActivity: Date(timeIntervalSince1970: TimeInterval(id)),
            type: .tipDm,
            isHidden: hidden
        )
    }

    @Test("setHidden flips the flag but retains the conversation")
    func setHiddenRetains() {
        var store = ConversationStore()
        let c = convo(1, hidden: false)
        store.setFeed([c])
        store.setHidden(true, in: c.id)
        #expect(store.conversations.count == 1)              // retained
        #expect(store.conversations.first?.isHidden == true) // flagged
    }
}
