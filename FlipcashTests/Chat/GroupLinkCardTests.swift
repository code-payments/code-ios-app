//
//  GroupLinkCardTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

/// What a group invite card shows: the chat's rule as its head card states it, and nothing from
/// the roster.
@MainActor
@Suite struct GroupLinkCardTests {

    private static let token = try! PublicKey([UInt8](repeating: 7, count: 32))

    private static func facts(
        title: String? = "Ballers",
        memberCount: UInt64 = 12,
        members: [ConversationMember] = [],
        rules: ConversationRules? = nil,
        mintName: String? = nil
    ) -> GroupLinkFacts {
        GroupLinkFacts(
            conversation: Conversation(
                id: ConversationID(data: Data(repeating: 0x01, count: 32)),
                members: members,
                lastMessage: nil,
                lastActivity: Date(timeIntervalSince1970: 0),
                type: .group,
                title: title,
                rosterSummary: ConversationRosterSummary(memberCount: memberCount, version: 0),
                rules: rules
            ),
            headlineMintName: mintName
        )
    }

    private static func balanceRule(_ amount: FiatAmount, mint: PublicKey) -> ConversationRules {
        ConversationRules(listener: [.minimumBalance(MinimumBalanceRequirement(amount: amount, mints: [mint]))])
    }

    @Test func aTokenRuleIsStatedWithTheTokenName() {
        let card = groupLinkCard(
            Self.facts(rules: Self.balanceRule(.usd(100), mint: Self.token), mintName: "$BadBoys"),
            imageData: nil
        )
        #expect(card.requirement == "Balance Requirement:\n$100 of $BadBoys")
    }

    @Test func aDollarRuleIsStatedByAmountAlone() {
        let card = groupLinkCard(Self.facts(rules: Self.balanceRule(.usd(100), mint: .usdf)), imageData: nil)
        #expect(card.requirement == "Balance Requirement:\n$100")
    }

    @Test func aStaffOnlyChatSaysSo() {
        let rules = ConversationRules(listener: [.staff])
        #expect(groupLinkCard(Self.facts(rules: rules), imageData: nil).requirement == "This chat is for Flipcash staff")
    }

    @Test func aChatWithNoRulesStatesNone() {
        #expect(groupLinkCard(Self.facts(), imageData: nil).requirement == nil)
    }

    @Test func theMemberCountComesFromTheSummaryNotTheRoster() {
        #expect(groupLinkCard(Self.facts(memberCount: 1), imageData: nil).memberCount == "1 person")
        #expect(groupLinkCard(Self.facts(memberCount: 240), imageData: nil).memberCount == "240 people")
    }

    /// `displayName(for:)` would build a name from the roster here; the card must not.
    @Test func anUntitledGroupIsNotNamedAfterItsMembers() {
        let member = ConversationMember(userID: nil, displayName: "Jane Doe")
        let card = groupLinkCard(Self.facts(title: "  ", members: [member]), imageData: nil)
        #expect(card.title == Conversation.untitledGroupLinkTitle)
    }
}
