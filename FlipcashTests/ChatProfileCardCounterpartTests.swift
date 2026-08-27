//
//  ChatProfileCardCounterpartTests.swift
//  FlipcashTests
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("Tip DM profile card counterpart")
struct ChatProfileCardCounterpartTests {

    @Test("A counterpart who has claimed a handle shows it")
    func claimedHandle_isShown() {
        let member = ConversationMember(
            userID: UUID(),
            displayName: "Fred Wilson",
            username: Username("fred_wilson")
        )
        #expect(ConversationScreen.tipDMCounterpart(member) == .handle(Username("fred_wilson")!))
    }

    @Test("A counterpart with no handle renders as it did before handles existed")
    func unclaimedHandle_fallsBackToNone() {
        // A handle can also go away across a profile refresh, and the card has
        // to survive that rather than show an empty line.
        let member = ConversationMember(userID: UUID(), displayName: "Fred Wilson")
        #expect(ConversationScreen.tipDMCounterpart(member) == ChatProfileCard.Counterpart.none)
    }

    @Test("A conversation with no counterpart at all renders the same way")
    func missingMember_fallsBackToNone() {
        #expect(ConversationScreen.tipDMCounterpart(nil) == ChatProfileCard.Counterpart.none)
    }
}
