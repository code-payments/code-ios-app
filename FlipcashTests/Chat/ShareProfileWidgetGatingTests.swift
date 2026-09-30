//
//  ShareProfileWidgetGatingTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Testing
import FlipcashCore
import FlipcashUI
import FlipcashStore
@testable import Flipcash

/// A widget's Reply and reactions follow the chat's speaker rule, evaluated by `conversationGate`
/// exactly as it is for the composer.
@MainActor
@Suite("Share-profile widget speaker gating")
struct ShareProfileWidgetGatingTests {

    private final class Holdings: ConversationGateReading {
        var isStaff: Bool
        var userID: UserID
        var totalBalance = ExchangedFiat(nativeAmount: .usd(0), rate: Rate(fx: 1, currency: .usd))
        init(isStaff: Bool = false, userID: UserID = UUID()) { self.isStaff = isStaff; self.userID = userID }
        func balance(for mint: PublicKey) -> StoredBalance? { nil }
    }

    private let me = UUID()
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func widget() throws -> ConversationMessage {
        ConversationMessage(
            id: MessageID(value: 1), senderID: nil,
            content: .widget(.shareProfile(ShareProfileWidget(username: try #require(Username("alice"))))),
            date: now, unreadSeq: 1, eventSequence: 1
        )
    }

    /// What the coordinator hands the mapper for a member under `rules`: the gate's verdict through
    /// `access(isMember:gate:)`, with the widget's actions and reaction flag resolved from it.
    private func offered(_ rules: ConversationRules, creator: UserID? = nil, holdings: Holdings = Holdings()) throws -> (actions: Set<MessageCapability>, canReact: Bool) {
        let gate = conversationGate(session: holdings, rules: rules, creator: creator, rates: [:])
        let access = ConversationLoadCoordinator.access(isMember: true, gate: gate)
        let message = try widget()
        let items = ChatItem.from(
            [message],
            selfUserID: me,
            capabilities: {
                MessageCapability.resolve(for: $0, in: nil, as: me, isMember: true, canPost: access.canPost, policy: .default, now: now)
            },
            canReact: access.canReact
        )
        for item in items {
            if case .message(let row) = item { return (Set(row.actions), row.canReact) }
        }
        Issue.record("no message row")
        return ([], false)
    }

    @Test("An open chat offers Reply and reactions")
    func openChat() throws {
        let result = try offered(ConversationRules())
        #expect(result.actions == [.reply])
        #expect(result.canReact)
    }

    @Test("A never speaker rule offers neither Reply nor reactions, even to staff")
    func neverRule() throws {
        let result = try offered(ConversationRules(speaker: [.never]), holdings: Holdings(isStaff: true))
        #expect(result.actions.isEmpty)
        #expect(!result.canReact)
    }

    @Test("An unmet balance requirement offers neither")
    func unmetBalance() throws {
        let rules = ConversationRules(speaker: [.minimumBalance(MinimumBalanceRequirement(amount: .usd(100), mints: []))])
        let result = try offered(rules)
        #expect(result.actions.isEmpty)
        #expect(!result.canReact)
    }

    @Test("An unmet staff requirement offers neither, and a staff member is offered both")
    func staffRule() throws {
        let rules = ConversationRules(speaker: [.staff])
        let blocked = try offered(rules)
        #expect(blocked.actions.isEmpty)
        #expect(!blocked.canReact)
        let allowed = try offered(rules, holdings: Holdings(isStaff: true))
        #expect(allowed.actions == [.reply])
        #expect(allowed.canReact)
    }

    @Test("A creator rule offers a non-creator reactions but no Reply, and the creator both")
    func creatorRule() throws {
        let rules = ConversationRules(speaker: [.creator])
        let other = try offered(rules, creator: UUID())
        #expect(other.actions.isEmpty)
        #expect(other.canReact)
        let nilCreator = try offered(rules, creator: nil)
        #expect(nilCreator.actions.isEmpty)
        #expect(nilCreator.canReact)
        let creator = try offered(rules, creator: me, holdings: Holdings(userID: me))
        #expect(creator.actions == [.reply])
        #expect(creator.canReact)
    }

    @Test("An unsupported rule offers reactions but no Reply, staff included")
    func unsupportedRule() throws {
        let result = try offered(ConversationRules(speaker: [.unsupported]), holdings: Holdings(isStaff: true))
        #expect(result.actions.isEmpty)
        #expect(result.canReact)
    }

    @Test("Creator paired with an unmet staff rule keeps reactions off")
    func creatorWithUnmetStaff() throws {
        let rules = ConversationRules(speaker: [.creator, .staff])
        let result = try offered(rules, creator: me, holdings: Holdings(userID: me))
        #expect(result.actions.isEmpty)
        #expect(!result.canReact)
    }

    @Test("A reply to a widget quotes it as \"Shared a profile\"")
    func replyQuote() throws {
        let original = try widget()
        let reply = ConversationMessage(
            id: MessageID(value: 2), senderID: me, content: .text("nice"),
            date: now.addingTimeInterval(5), unreadSeq: 2, eventSequence: 2, repliedTo: original.id
        )
        let items = ChatItem.from([original, reply], selfUserID: me, quotedMessage: { $0 == original.id ? original : nil })
        let quote = items.compactMap { item -> ChatQuote? in
            if case .message(let row) = item { return row.quote } else { return nil }
        }.last
        #expect(quote?.snippet == "Shared a profile")
    }
}
