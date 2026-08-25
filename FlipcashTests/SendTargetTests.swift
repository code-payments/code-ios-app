//
//  SendTargetTests.swift
//  FlipcashTests
//

import Testing
import Foundation
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("SendTarget(conversation:dmChatID:selfUserID:)")
struct SendTargetTests {

    private let chatID = Data([0xDE, 0xAD, 0xBE, 0xEF])

    private func makeConversation(type: ConversationType, members: [ConversationMember]) -> Conversation {
        Conversation(
            id: ConversationID(data: Data(repeating: 0x01, count: 32)),
            members: members,
            lastMessage: nil,
            lastActivity: Date(timeIntervalSince1970: 0),
            type: type
        )
    }

    @Test("A tip DM counterpart with a claimed handle carries it onto the tip target")
    func tipDMCounterpartWithHandleCarriesUsername() throws {
        let me = UUID()
        let counterpartID = UUID()
        let convo = makeConversation(type: .tipDm, members: [
            ConversationMember(userID: me, displayName: "Me"),
            ConversationMember(userID: counterpartID, displayName: "Alice", username: Username("alice")),
        ])

        let target = try #require(SendTarget(conversation: convo, dmChatID: chatID, selfUserID: me))

        guard case .tip(let recipient) = target else {
            Issue.record("Expected .tip")
            return
        }
        #expect(recipient.userID == counterpartID)
        #expect(recipient.displayName == "Alice")
        #expect(recipient.username == Username("alice"))
        #expect(recipient.origin == .chat)
    }

    @Test("A tip DM counterpart with no claimed handle yields a tip target with no username")
    func tipDMCounterpartWithoutHandleYieldsNilUsername() throws {
        let me = UUID()
        let counterpartID = UUID()
        let convo = makeConversation(type: .tipDm, members: [
            ConversationMember(userID: me, displayName: "Me"),
            ConversationMember(userID: counterpartID, displayName: "Alice"),
        ])

        let target = try #require(SendTarget(conversation: convo, dmChatID: chatID, selfUserID: me))

        guard case .tip(let recipient) = target else {
            Issue.record("Expected .tip")
            return
        }
        #expect(recipient.username == nil)
    }

    @Test("A tip DM resolves to the member that isn't the signed-in user")
    func tipDMResolvesCounterpartExcludingSelf() throws {
        let me = UUID()
        let counterpartID = UUID()
        let convo = makeConversation(type: .tipDm, members: [
            ConversationMember(userID: counterpartID, displayName: "Alice"),
            ConversationMember(userID: me, displayName: "Me"),
        ])

        let target = try #require(SendTarget(conversation: convo, dmChatID: chatID, selfUserID: me))

        guard case .tip(let recipient) = target else {
            Issue.record("Expected .tip")
            return
        }
        #expect(recipient.userID == counterpartID)
    }

    @Test("A tip DM counterpart with no user id yields no target")
    func tipDMCounterpartWithoutUserIDYieldsNil() {
        let me = UUID()
        let convo = makeConversation(type: .tipDm, members: [
            ConversationMember(userID: me, displayName: "Me"),
            ConversationMember(userID: nil, displayName: "Alice"),
        ])

        #expect(SendTarget(conversation: convo, dmChatID: chatID, selfUserID: me) == nil)
    }

    @Test("A group conversation has no single counterpart to pay")
    func groupConversationYieldsNil() {
        let me = UUID()
        let convo = makeConversation(type: .group, members: [
            ConversationMember(userID: me, displayName: "Me"),
            ConversationMember(userID: UUID(), displayName: "Alice"),
            ConversationMember(userID: UUID(), displayName: "Bob"),
        ])

        #expect(SendTarget(conversation: convo, dmChatID: chatID, selfUserID: me) == nil)
    }

    @Test("A contact DM resolves through ResolvedContact rather than the tip path")
    func contactDMResolvesThroughResolvedContact() throws {
        let me = UUID()
        let convo = makeConversation(type: .contactDm, members: [
            ConversationMember(userID: me, displayName: "Me"),
            ConversationMember(userID: UUID(), displayName: "", phoneE164: "+15551234567"),
        ])

        let target = try #require(SendTarget(conversation: convo, dmChatID: chatID, selfUserID: me))

        guard case .contact(let resolved) = target else {
            Issue.record("Expected .contact")
            return
        }
        #expect(resolved.phoneE164 == "+15551234567")
    }

    @Test("A nil conversation falls through to the contact path and yields no target")
    func nilConversationYieldsNil() {
        #expect(SendTarget(conversation: nil, dmChatID: chatID, selfUserID: UUID()) == nil)
    }
}
