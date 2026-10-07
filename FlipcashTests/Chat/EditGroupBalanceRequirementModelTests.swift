//
//  EditGroupBalanceRequirementModelTests.swift
//  FlipcashTests
//

import Testing
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("Group balance requirement editor")
struct EditGroupBalanceRequirementModelTests {

    private struct Boom: Error {}

    @MainActor
    private final class Calls {
        var requirements: [MinimumBalanceRequirement] = []
    }

    private let token = PublicKey.jeffy

    private let rates: [CurrencyCode: Rate] = [
        .usd: Rate(fx: 1, currency: .usd),
        .cad: Rate(fx: 1.25, currency: .cad),
    ]

    private func makeModel(
        role: GroupBalanceRole = .join,
        current: MinimumBalanceRequirement? = nil,
        currency: CurrencyCode = .usd,
        calls: Calls = Calls(),
        saving: ((MinimumBalanceRequirement) async throws -> Void)? = nil
    ) -> EditGroupBalanceRequirementModel {
        EditGroupBalanceRequirementModel(role: role, current: current, currency: currency, rates: rates) { requirement in
            calls.requirements.append(requirement)
            try await saving?(requirement)
        }
    }

    @Test("The keypad opens on the current requirement, restated in the entry currency")
    func seedsFromCurrent() {
        #expect(makeModel(current: .init(amount: .usd(5))).enteredAmount == "5")
        #expect(makeModel(current: .init(amount: .usd(5)), currency: .cad).enteredAmount == "6.25")
        #expect(makeModel().enteredAmount == "")
    }

    @Test("Save is shut while empty, zero, or unchanged")
    func canSave() {
        let model = makeModel(current: .init(amount: .usd(5)))
        #expect(!model.canSave)

        model.enteredAmount = "0"
        #expect(!model.canSave)

        model.enteredAmount = "10"
        #expect(model.canSave)
    }

    @Test("The entry is saved in USD and keeps the mint the requirement names")
    func savesInUSDKeepingMint() async {
        let calls = Calls()
        let model = makeModel(current: .init(amount: .usd(5), mints: [token]), currency: .cad, calls: calls)
        model.enteredAmount = "12.50"

        await model.save()

        #expect(calls.requirements == [.init(amount: .usd(10), mints: [token])])
        #expect(model.state == .saved)
    }

    @Test("A group with no requirement gets one across all holdings")
    func newRequirementAppliesToAllHoldings() async {
        let calls = Calls()
        let model = makeModel(role: .chat, calls: calls)
        model.enteredAmount = "3"

        await model.save()

        #expect(calls.requirements == [.init(amount: .usd(3), mints: [])])
    }

    @Test("The stub's refusal surfaces as unavailable and leaves Save open")
    func stubIsUnavailable() async {
        let model = makeModel { _ in throw ErrorSetGroupMinimumBalance.unavailable }
        model.enteredAmount = "3"

        await model.save()

        #expect(model.failure == .unavailable)
        #expect(model.state == .normal)
        #expect(model.canSave)
    }

    @Test("Any other failure surfaces as failed")
    func otherFailure() async {
        let model = makeModel { _ in throw Boom() }
        model.enteredAmount = "3"

        await model.save()

        #expect(model.failure == .failed)
        #expect(model.state == .normal)
    }
}
