//
//  ResolvedContactCounterpartTests.swift
//  FlipcashTests
//

import Testing
import Foundation
import FlipcashCore
@testable import Flipcash

@Suite("ResolvedContact(counterpart:dmChatID:)")
struct ResolvedContactCounterpartTests {

    private let chatID = Data([0xDE, 0xAD, 0xBE, 0xEF])

    @Test("Builds a send target from a counterpart's phone number")
    func buildsTargetFromPhone() throws {
        let member = ConversationMember(userID: UUID(), displayName: "", phoneE164: "+14155550100")

        let target = try #require(ResolvedContact(counterpart: member, dmChatID: chatID))

        #expect(target.phoneE164 == "+14155550100")
        #expect(target.dmChatID == chatID)
        #expect(target.nationalPhone == member.formattedPhoneNumber)
        #expect(target.displayName == member.formattedPhoneNumber)
        #expect(target.imageData == nil)
    }

    @Test("Falls back to the raw E.164 when the number can't be parsed")
    func fallsBackToRawNumber() throws {
        let member = ConversationMember(userID: UUID(), displayName: "", phoneE164: "+1")

        let target = try #require(ResolvedContact(counterpart: member, dmChatID: chatID))

        #expect(target.phoneE164 == "+1")
        #expect(target.nationalPhone == "+1")
    }

    @Test("A missing or empty phone number yields no target", arguments: [nil, ""] as [String?])
    func noUsablePhoneYieldsNil(phone: String?) {
        let member = ConversationMember(userID: UUID(), displayName: "Alice", phoneE164: phone)

        #expect(ResolvedContact(counterpart: member, dmChatID: chatID) == nil)
    }

    @Test("sendTarget builds the target from the conversation's counterpart phone")
    func sendTargetFromCounterpart() {
        let id = ConversationID(data: Data(repeating: 0x01, count: 32))
        let me = UUID()
        let convo = Conversation(
            id: id,
            members: [
                ConversationMember(userID: me, displayName: "Me"),
                ConversationMember(userID: UUID(), displayName: "", phoneE164: "+15551234567"),
            ],
            lastMessage: nil,
            lastActivity: Date(timeIntervalSince1970: 0)
        )

        let target = ResolvedContact.sendTarget(in: convo, dmChatID: id.data, selfUserID: me)

        #expect(target?.phoneE164 == "+15551234567")
        #expect(target?.dmChatID == id.data)
    }

    @Test("sendTarget yields nil when the conversation has no counterpart")
    func sendTargetNoCounterpart() {
        let id = ConversationID(data: Data(repeating: 0x02, count: 32))
        let me = UUID()
        let convo = Conversation(
            id: id,
            members: [ConversationMember(userID: me, displayName: "Me")],
            lastMessage: nil,
            lastActivity: Date(timeIntervalSince1970: 0)
        )

        #expect(ResolvedContact.sendTarget(in: convo, dmChatID: id.data, selfUserID: me) == nil)
    }
}
