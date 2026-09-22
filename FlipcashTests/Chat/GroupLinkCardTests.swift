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

/// What a group invite card shows for a given viewer: the button follows the same gate the chat's
/// own screen evaluates, and nothing on the card comes from the roster.
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

    private static func blocked(_ requirement: ConversationGateRequirement) -> ConversationGate {
        ConversationGate(
            listener: .unsatisfied(unmet: [requirement], primary: requirement),
            speaker: .satisfied,
            headline: requirement
        )
    }

    @Test func aMemberIsOfferedTheChat() {
        let card = groupLinkCard(Self.facts(), gate: .open, isMember: true, imageData: nil)
        #expect(card.action == .open)
    }

    @Test func anEligibleNonMemberIsOfferedTheJoin() {
        let card = groupLinkCard(Self.facts(), gate: .open, isMember: false, imageData: nil)
        #expect(card.action == .join)
    }

    @Test func aViewerShortOfTheNamedTokenIsOfferedThatToken() {
        let requirement = ConversationGateRequirement.minimumBalance(amount: .usd(100), mint: Self.token)
        let card = groupLinkCard(
            Self.facts(mintName: "$BadBoys"),
            gate: Self.blocked(requirement),
            isMember: false,
            imageData: nil
        )
        #expect(card.action == .getToken(name: "$BadBoys"))
        #expect(card.requirement == "Balance Requirement:\n$100 of $BadBoys")
    }

    @Test func aViewerShortOfATokenTheCardCannotNameIsOfferedNothing() {
        let requirement = ConversationGateRequirement.minimumBalance(amount: .usd(100), mint: Self.token)
        let card = groupLinkCard(Self.facts(mintName: nil), gate: Self.blocked(requirement), isMember: false, imageData: nil)
        #expect(card.action == .none)
    }

    @Test func aViewerShortOfDollarsIsOfferedCash() {
        let requirement = ConversationGateRequirement.minimumBalance(amount: .usd(100), mint: .usdf)
        let card = groupLinkCard(Self.facts(), gate: Self.blocked(requirement), isMember: false, imageData: nil)
        #expect(card.action == .addCash)
        #expect(card.requirement == "Balance Requirement:\n$100")
    }

    @Test func aStaffOnlyChatOffersNoButton() {
        let card = groupLinkCard(Self.facts(), gate: Self.blocked(.staff), isMember: false, imageData: nil)
        #expect(card.action == .none)
        #expect(card.requirement == "This chat is for Flipcash staff")
    }

    @Test func theMemberCountComesFromTheSummaryNotTheRoster() {
        #expect(groupLinkCard(Self.facts(memberCount: 1), gate: .open, isMember: false, imageData: nil).memberCount == "1 person")
        #expect(groupLinkCard(Self.facts(memberCount: 240), gate: .open, isMember: false, imageData: nil).memberCount == "240 people")
    }

    /// `displayName(for:)` would build a name from the roster here; the card must not.
    @Test func anUntitledGroupIsNotNamedAfterItsMembers() {
        let member = ConversationMember(userID: nil, displayName: "Jane Doe")
        let card = groupLinkCard(Self.facts(title: "  ", members: [member]), gate: .open, isMember: false, imageData: nil)
        #expect(card.title == Conversation.untitledGroupLinkTitle)
    }
}
