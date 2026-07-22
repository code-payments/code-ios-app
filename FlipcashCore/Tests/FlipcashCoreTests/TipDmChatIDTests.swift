//
//  TipDmChatIDTests.swift
//  FlipcashCoreTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
@testable import FlipcashCore

/// Vectors mirror the server's `MustDeriveDmChatID(TIP_DM, a, b)`:
/// SHA-256 over the domain `"flipcash:chat:dm:2"` followed by the sorted set
/// of the two 16-byte user IDs. The server rejects any tip intent whose chat
/// id doesn't match this derivation, so these bytes are a wire contract.
@Suite("Tip DM chat ID derivation")
struct TipDmChatIDTests {

    private let userA = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    private let userB = UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!

    @Test("Matches the server's derivation for a sorted pair")
    func derivesServerVector() {
        let id = ConversationID.tipDm(between: userA, and: userB)

        #expect(id.data.hexString() == "8b2f0e5da9fa050dc0040fb23dc0aa0028a0c5d9fca36b50cd3c163be3cb09e7")
    }

    @Test("Argument order does not change the ID")
    func orderIndependent() {
        let ab = ConversationID.tipDm(between: userA, and: userB)
        let ba = ConversationID.tipDm(between: userB, and: userA)

        #expect(ab == ba)
    }

    @Test("A self-pair collapses to a single member")
    func selfPairCollapses() {
        let id = ConversationID.tipDm(between: userA, and: userA)

        #expect(id.data.hexString() == "525de420ef8a70e1cf1483090f937d7563a7bbe7501558ab5f6aae59780c3af2")
    }

    @Test("Produces the 32-byte ChatId length")
    func producesChatIDLength() {
        let id = ConversationID.tipDm(between: userA, and: userB)

        #expect(id.data.count == 32)
    }
}
