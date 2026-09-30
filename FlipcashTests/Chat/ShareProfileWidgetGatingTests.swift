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
        var totalBalance = ExchangedFiat(nativeAmount: .usd(0), rate: Rate(fx: 1, currency: .usd))
        init(isStaff: Bool = false) { self.isStaff = isStaff }
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

    /// What the screen hands the coordinator: whether the viewer, a member, may speak under `rules`.
    private func canSpeak(_ rules: ConversationRules, holdings: Holdings = Holdings()) -> Bool {
        conversationGate(session: holdings, rules: rules, rates: [:]).isOpen
    }

    private func offered(canSpeak: Bool) throws -> (actions: Set<MessageCapability>, canReact: Bool) {
        let message = try widget()
        let items = ChatItem.from(
            [message],
            selfUserID: me,
            capabilities: {
                MessageCapability.resolve(for: $0, in: nil, as: me, isMember: true, canSpeak: canSpeak, policy: .default, now: now)
            },
            canSpeak: canSpeak
        )
        for item in items {
            if case .message(let row) = item { return (Set(row.actions), row.canReact) }
        }
        Issue.record("no message row")
        return ([], false)
    }

    @Test("An open chat offers Reply and reactions")
    func openChat() throws {
        #expect(canSpeak(ConversationRules()))
        let result = try offered(canSpeak: true)
        #expect(result.actions == [.reply])
        #expect(result.canReact)
    }

    @Test("A never speaker rule offers neither Reply nor reactions")
    func neverRule() throws {
        let rules = ConversationRules(speaker: [.never])
        #expect(!canSpeak(rules, holdings: Holdings(isStaff: true)))
        let result = try offered(canSpeak: canSpeak(rules))
        #expect(result.actions.isEmpty)
        #expect(!result.canReact)
    }

    @Test("An unmet balance requirement offers neither")
    func unmetBalance() throws {
        let rules = ConversationRules(speaker: [.minimumBalance(MinimumBalanceRequirement(amount: .usd(100), mints: []))])
        #expect(!canSpeak(rules))
        let result = try offered(canSpeak: canSpeak(rules))
        #expect(result.actions.isEmpty)
        #expect(!result.canReact)
    }

    @Test("An unmet staff requirement offers neither, and a staff member is offered both")
    func staffRule() throws {
        let rules = ConversationRules(speaker: [.staff])
        #expect(!canSpeak(rules))
        #expect(canSpeak(rules, holdings: Holdings(isStaff: true)))
        let result = try offered(canSpeak: canSpeak(rules))
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
