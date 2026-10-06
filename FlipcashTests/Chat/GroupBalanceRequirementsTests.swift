//
//  GroupBalanceRequirementsTests.swift
//  FlipcashTests
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("Group balance requirements card")
struct GroupBalanceRequirementsTests {

    private func minimum(_ usd: Decimal) -> MinimumBalanceRequirement {
        MinimumBalanceRequirement(amount: .usd(usd), mints: [])
    }

    @Test("Join and Chat read their own sides when both are set")
    func bothSides() {
        let requirements = GroupBalanceRequirements(rules: ConversationRules(
            listener: [.minimumBalance(minimum(5))],
            speaker: [.minimumBalance(minimum(20))]
        ))

        #expect(requirements?.join == minimum(5))
        #expect(requirements?.chat == minimum(20))
    }

    @Test("Chat falls back to Join when the group sets no speaker minimum")
    func chatFallsBackToJoin() {
        let requirements = GroupBalanceRequirements(rules: ConversationRules(
            listener: [.minimumBalance(minimum(5))],
            speaker: [.creator]
        ))

        #expect(requirements?.chat == minimum(5))
    }

    @Test("The card is hidden when neither side states a minimum")
    func hiddenWithoutMinimum() {
        #expect(GroupBalanceRequirements(rules: ConversationRules(speaker: [.never])) == nil)
        #expect(GroupBalanceRequirements(rules: nil) == nil)
    }
}
