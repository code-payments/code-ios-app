//
//  E2eePolicyTests.swift
//  FlipcashCoreTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
@testable import FlipcashCore

@Suite("E2eePolicy")
struct E2eePolicyTests {

    private static let flipcashID = UUID()

    private func conversation(type: ConversationType, useE2Ee: Bool, memberIDs: [UUID] = [UUID(), UUID()]) -> Conversation {
        Conversation(
            id: ConversationID(data: Data(repeating: 1, count: 32)),
            members: memberIDs.map { ConversationMember(userID: $0, displayName: "m") },
            lastMessage: nil,
            lastActivity: Date(timeIntervalSince1970: 0),
            type: type,
            useE2Ee: useE2Ee
        )
    }

    @Test("A DM with the flag on encrypts", arguments: [ConversationType.contactDm, .tipDm])
    func dmFlagOn(type: ConversationType) {
        #expect(E2eePolicy.shouldEncrypt(conversation(type: type, useE2Ee: true), flipcashAccountID: Self.flipcashID))
    }

    @Test("A DM with the flag off does not encrypt", arguments: [ConversationType.contactDm, .tipDm])
    func dmFlagOff(type: ConversationType) {
        #expect(!E2eePolicy.shouldEncrypt(conversation(type: type, useE2Ee: false), flipcashAccountID: Self.flipcashID))
    }

    @Test("A group never encrypts, even with the flag on")
    func groupFlagOn() {
        #expect(!E2eePolicy.shouldEncrypt(conversation(type: .group, useE2Ee: true), flipcashAccountID: Self.flipcashID))
    }

    @Test("The @flipcash chat never encrypts, even with the flag on")
    func flipcashFlagOn() {
        let chat = conversation(type: .contactDm, useE2Ee: true, memberIDs: [UUID(), Self.flipcashID])
        #expect(!E2eePolicy.shouldEncrypt(chat, flipcashAccountID: Self.flipcashID))
    }

    @Test("Until the @flipcash id is set, no chat is exempt")
    func flipcashIDUnset() {
        let chat = conversation(type: .contactDm, useE2Ee: true, memberIDs: [UUID(), Self.flipcashID])
        #expect(E2eePolicy.shouldEncrypt(chat, flipcashAccountID: nil))
    }
}
