//
//  GroupProfileStateTests.swift
//  FlipcashTests
//

import Foundation
import Testing
@testable import Flipcash
import FlipcashCore
import FlipcashStore

@MainActor
@Suite("Group profile state")
struct GroupProfileStateTests {

    private let noRates: [CurrencyCode: Rate] = [:]

    private func minimum(_ usd: Decimal, mints: [PublicKey] = []) -> MinimumBalanceRequirement {
        MinimumBalanceRequirement(amount: .usd(usd), mints: mints)
    }

    private func gate(
        listener: [ConversationListenerRule] = [],
        speaker: [ConversationSpeakerRule] = [],
        holdings: StubGateHoldings = StubGateHoldings(),
        rates: [CurrencyCode: Rate] = [:]
    ) -> ConversationGate {
        conversationGate(
            session: holdings,
            rules: ConversationRules(listener: listener, speaker: speaker),
            rates: rates
        )
    }

    // MARK: - Pinned button

    @Test("A non-member short of the join minimum is offered the buy to join")
    func nonMemberShortOfJoin() {
        let gate = gate(listener: [.minimumBalance(minimum(10))])

        #expect(GroupProfileCTA.resolve(gate: gate, isMember: false) == .buyToJoin(amount: .usd(10), mint: nil))
    }

    @Test("A non-member who meets the join minimum is offered Join")
    func nonMemberEligible() {
        let gate = gate(listener: [.minimumBalance(minimum(10))], holdings: StubGateHoldings(totalUSD: 12))

        #expect(GroupProfileCTA.resolve(gate: gate, isMember: false) == .join)
    }

    @Test("A non-member of a group with no rules is offered Join")
    func nonMemberNoRules() {
        #expect(GroupProfileCTA.resolve(gate: .open, isMember: false) == .join)
    }

    @Test("A non-member held out by a rule they can't buy past gets no button")
    func nonMemberStaffOnly() {
        let gate = gate(listener: [.staff])

        #expect(GroupProfileCTA.resolve(gate: gate, isMember: false) == .none)
    }

    @Test("A non-member waits for a rate before the button commits to Join")
    func nonMemberProvisional() {
        let rule = MinimumBalanceRequirement(amount: FiatAmount(value: 10, currency: .cad))
        let gate = gate(listener: [.minimumBalance(rule)], rates: noRates)

        #expect(gate.isProvisional)
        #expect(GroupProfileCTA.resolve(gate: gate, isMember: false) == .none)
    }

    @Test("A member who can speak is offered Open Chat")
    func memberCanSpeak() {
        let gate = gate(speaker: [.minimumBalance(minimum(100))], holdings: StubGateHoldings(totalUSD: 100))

        #expect(GroupProfileCTA.resolve(gate: gate, isMember: true) == .openChat)
    }

    @Test("A member short of the chat minimum is offered the buy to chat")
    func memberShortOfChat() {
        let gate = gate(
            listener: [.minimumBalance(minimum(10))],
            speaker: [.minimumBalance(minimum(100))],
            holdings: StubGateHoldings(totalUSD: 12)
        )

        #expect(GroupProfileCTA.resolve(gate: gate, isMember: true) == .buyToChat(amount: .usd(100), mint: nil))
    }

    @Test("A member short of both minimums is asked for the chat one, which covers the join one")
    func memberShortOfBoth() {
        let gate = gate(
            listener: [.minimumBalance(minimum(10))],
            speaker: [.minimumBalance(minimum(100))]
        )

        #expect(GroupProfileCTA.resolve(gate: gate, isMember: true) == .buyToChat(amount: .usd(100), mint: nil))
    }

    @Test("A member who fell under the join minimum of a group with no chat minimum buys up to the join one")
    func memberUnderJoinOnly() {
        let gate = gate(listener: [.minimumBalance(minimum(10))])

        #expect(GroupProfileCTA.resolve(gate: gate, isMember: true) == .buyToChat(amount: .usd(10), mint: nil))
    }

    @Test("A member of a read-only group still gets Open Chat")
    func memberReadOnly() {
        let gate = gate(speaker: [.never])

        #expect(GroupProfileCTA.resolve(gate: gate, isMember: true) == .openChat)
    }

    // MARK: - Balance requirements card

    @Test("Join is the listener minimum and Chat the speaker minimum")
    func requirementsBoth() {
        let rules = ConversationRules(
            listener: [.minimumBalance(minimum(10))],
            speaker: [.minimumBalance(minimum(100))]
        )

        let requirements = GroupBalanceRequirements(rules)
        #expect(requirements?.join == minimum(10))
        #expect(requirements?.chat == minimum(100))
    }

    @Test("Chat falls back to the join minimum when the group sets no chat minimum")
    func requirementsChatFallsBackToJoin() {
        let rules = ConversationRules(listener: [.minimumBalance(minimum(10))], speaker: [.staff])

        let requirements = GroupBalanceRequirements(rules)
        #expect(requirements?.join == minimum(10))
        #expect(requirements?.chat == minimum(10))
    }

    @Test("A chat minimum with no join minimum leaves Join empty")
    func requirementsChatOnly() {
        let rules = ConversationRules(speaker: [.minimumBalance(minimum(100))])

        let requirements = GroupBalanceRequirements(rules)
        #expect(requirements?.join == nil)
        #expect(requirements?.chat == minimum(100))
    }

    @Test("The card is hidden for a group with no minimum balance rule", arguments: [
        nil,
        ConversationRules(),
        ConversationRules(listener: [.staff], speaker: [.never]),
    ])
    func requirementsHidden(rules: ConversationRules?) {
        #expect(GroupBalanceRequirements(rules) == nil)
    }

    // MARK: - Shortfall

    @Test("The shortfall is the requirement less what is held")
    func shortfallAcrossHoldings() {
        let holdings = StubGateHoldings(totalUSD: Decimal(string: "6.33")!)

        let shortfall = balanceShortfall(of: .usd(10), mint: nil, holdings: holdings, rates: noRates)
        #expect(shortfall == .usd(Decimal(string: "3.67")!))
    }

    @Test("A requirement on one mint counts only that mint's holding")
    func shortfallOneMint() throws {
        let holdings = StubGateHoldings(totalUSD: 50, balances: [.usdf: try .usdfHolding(usd: 4)])

        let shortfall = balanceShortfall(of: .usd(10), mint: .usdf, holdings: holdings, rates: noRates)
        #expect(shortfall == .usd(6))
    }

    @Test("A requirement in another currency states its shortfall in that currency")
    func shortfallRestated() {
        let rates: [CurrencyCode: Rate] = [.cad: Rate(fx: Decimal(string: "1.4")!, currency: .cad)]
        let holdings = StubGateHoldings(totalUSD: 5)

        let shortfall = balanceShortfall(of: FiatAmount(value: 14, currency: .cad), mint: nil, holdings: holdings, rates: rates)
        #expect(shortfall == FiatAmount(value: 7, currency: .cad))
    }

    @Test("There is no shortfall once the requirement is met")
    func shortfallMet() {
        let holdings = StubGateHoldings(totalUSD: 10)

        #expect(balanceShortfall(of: .usd(10), mint: nil, holdings: holdings, rates: noRates) == nil)
    }

    // MARK: - Chatting grid

    private func chatter() -> SampledChatter {
        SampledChatter(userID: UUID(), profile: Profile(displayName: "Fred", phone: Phone?.none, email: nil), lastSentAt: nil, isCreator: true)
    }

    @Test("A private group never shows the grid, whatever was sampled")
    func gridPrivate() {
        #expect(!GroupChattingGrid.isVisible(isPrivate: true, chatters: [chatter()]))
    }

    @Test("An empty sample hides the grid")
    func gridEmpty() {
        #expect(!GroupChattingGrid.isVisible(isPrivate: false, chatters: []))
    }

    @Test("A public group with a sample shows the grid")
    func gridShown() {
        #expect(GroupChattingGrid.isVisible(isPrivate: false, chatters: [chatter()]))
    }
}
