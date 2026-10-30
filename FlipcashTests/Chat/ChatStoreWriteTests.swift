//
//  ChatStoreWriteTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Testing
import FlipcashCore

@Suite("ChatStoreWrite")
struct ChatStoreWriteTests {

    private func message(_ id: UInt64, sequence: UInt64, text: String = "hi") -> ConversationMessage {
        ConversationMessage(id: MessageID(value: id), senderID: nil, content: .text(text), date: Date(timeIntervalSince1970: TimeInterval(id)), unreadSeq: id, eventSequence: sequence)
    }

    @Test("A delta that ran to its end advances the cursor to the head")
    func completeDeltaAdvancesCursor() {
        let write = ChatStoreWrite(preview: [message(3, sequence: 3)], delta: ChatDeltaPage(messages: [message(2, sequence: 2)], head: 4, isComplete: true))
        #expect(write.cursor == 4)
        #expect(write.messages.map(\.id.value) == [3, 2])
    }

    @Test("A delta cut off at its cap leaves the cursor alone")
    func cappedDeltaLeavesCursor() {
        let write = ChatStoreWrite(preview: [], delta: ChatDeltaPage(messages: [message(2, sequence: 2)], head: 9, isComplete: false))
        #expect(write.cursor == 0)
        #expect(write.messages.map(\.id.value) == [2])
    }

    @Test("A preview alone leaves the cursor alone")
    func previewAloneLeavesCursor() {
        #expect(ChatStoreWrite(preview: [message(3, sequence: 3)], delta: nil).cursor == 0)
    }

    @Test("A message in both sources is written once, as its newest version")
    func overlapKeepsNewestVersion() {
        let edited = message(3, sequence: 7, text: "edited")
        let write = ChatStoreWrite(preview: [message(3, sequence: 3)], delta: ChatDeltaPage(messages: [edited], head: 7, isComplete: true))
        #expect(write.messages == [edited])
    }
}
