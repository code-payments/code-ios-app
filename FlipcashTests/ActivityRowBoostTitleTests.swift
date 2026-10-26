//
//  ActivityRowBoostTitleTests.swift
//  FlipcashTests
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@Suite("Boosted reaction row title")
struct ActivityRowBoostTitleTests {

    private func boost(_ emoji: String) -> Activity.BoostedReaction {
        Activity.BoostedReaction(
            conversationID: ConversationID(data: Data(repeating: 1, count: 16)),
            messageID: MessageID(value: 7),
            emoji: emoji
        )
    }

    private func title(
        _ kind: Activity.Kind,
        emoji: String?,
        name: String?,
        chat: String? = nil,
        server: String
    ) -> String? {
        ActivityRow.title(
            kind: kind,
            boostedReaction: emoji.map(boost),
            name: name,
            chatName: chat,
            serverTitle: server
        )
    }

    @Test("1: sent boost with a resolved name")
    func sentNamed() {
        #expect(title(.gave, emoji: "🔥", name: "Sally", server: "Sent to Sally") == "Boosted 🔥 for Sally")
    }

    @Test("2: received boost with a resolved name")
    func receivedNamed() {
        #expect(title(.received, emoji: "🔥", name: "Sally", server: "Received from Sally") == "Boost 🔥 from Sally")
    }

    @Test("3: split boost names the chat")
    func splitWithChat() {
        #expect(title(.gave, emoji: "🔥", name: nil, chat: "Design Team", server: "Sent") == "Boosted 🔥 in Design Team")
    }

    @Test("4: split boost with no chat to name")
    func splitWithoutChat() {
        #expect(title(.gave, emoji: "🔥", name: nil, server: "Sent") == "Boosted 🔥")
        #expect(title(.gave, emoji: "🔥", name: nil, chat: "", server: "Sent") == "Boosted 🔥")
    }

    @Test("5: received boost with an unresolved name")
    func receivedUnresolved() {
        #expect(title(.received, emoji: "🔥", name: nil, server: "Received") == "Boost 🔥 received")
        #expect(title(.received, emoji: "🔥", name: "", server: "Received") == "Boost 🔥 received")
    }

    @Test("6: a boost wins over the tip verb, and the emoji is rendered verbatim")
    func boostWinsOverTip() {
        #expect(title(.gave, emoji: "👍🏽", name: "Sally", server: "Tipped Sally") == "Boosted 👍🏽 for Sally")
    }

    @Test("7: a tip without a boost is unchanged")
    func tipUnchanged() {
        #expect(title(.gave, emoji: nil, name: "Sally", server: "Tipped Sally") == "Tipped Sally")
    }

    @Test("8: a receive without a boost is unchanged")
    func receiveUnchanged() {
        #expect(title(.received, emoji: nil, name: "Sally", server: "Received from Sally") == "Received from Sally")
    }

    @Test("A kind that cannot carry a boost falls back to the server title")
    func otherKindFallsBack() {
        #expect(title(.bought, emoji: "🔥", name: "Sally", server: "Purchased") == nil)
    }
}
