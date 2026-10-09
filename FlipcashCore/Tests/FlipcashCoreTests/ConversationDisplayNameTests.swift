//
//  ConversationDisplayNameTests.swift
//  FlipcashCoreTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Testing
@testable import FlipcashCore

@Suite("Conversation display name")
struct ConversationDisplayNameTests {

    private let me = UUID()
    private let peer = UUID()

    private func conversation(type: ConversationType = .contactDm, title: String? = nil, peerName: String = "Peer") -> Conversation {
        var conversation = Conversation(
            id: ConversationID(data: Data(repeating: 1, count: 32)),
            members: [
                ConversationMember(userID: me, displayName: "Me"),
                ConversationMember(userID: peer, displayName: peerName),
            ],
            lastMessage: nil,
            lastActivity: .now,
            type: type,
            isHidden: false
        )
        conversation.title = title
        return conversation
    }

    @Test("A group's title wins over the contact lookup")
    func titleWins() {
        let name = conversation(type: .group, title: "Crew").displayName(selfUserID: me) { _ in "Contact" }
        #expect(name == "Crew")
    }

    @Test("The injected contact name wins over the feed's member name")
    func contactNameWins() {
        #expect(conversation().displayName(selfUserID: me) { _ in "Contact" } == "Contact")
    }

    @Test("An empty contact name falls through to the member name")
    func emptyContactFallsThrough() {
        #expect(conversation().displayName(selfUserID: me) { _ in "" } == "Peer")
    }

    @Test("A tip DM never asks for a contact name")
    func tipDmSkipsLookup() {
        var asked = false
        let name = conversation(type: .tipDm).displayName(selfUserID: me) { _ in asked = true; return "Contact" }
        #expect(!asked)
        #expect(name == "Peer")
    }

    @Test("A counterpart with no name falls back to the generic name")
    func genericFallback() {
        #expect(conversation(peerName: "").displayName(selfUserID: me) { _ in nil } == Conversation.fallbackCounterpartName)
    }
}
