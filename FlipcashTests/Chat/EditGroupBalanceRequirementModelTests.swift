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
        var amounts: [FiatAmount?] = []
    }

    private let token = PublicKey.jeffy

    private let rates: [CurrencyCode: Rate] = [
        .usd: Rate(fx: 1, currency: .usd),
        .cad: Rate(fx: 1.25, currency: .cad),
        .jpy: Rate(fx: 150, currency: .jpy),
    ]

    private func makeModel(
        role: GroupBalanceRole = .join,
        join: FiatAmount = .usd(5),
        speaker: FiatAmount? = nil,
        currency: CurrencyCode = .usd,
        satisfies: @escaping (ConversationRules) -> Bool? = { _ in true },
        calls: Calls = Calls(),
        saving: ((FiatAmount?) async throws -> Void)? = nil
    ) -> EditGroupBalanceRequirementModel {
        EditGroupBalanceRequirementModel(
            role: role,
            join: MinimumBalanceRequirement(amount: join, mints: [token]),
            speaker: speaker.map { MinimumBalanceRequirement(amount: $0, mints: [token]) },
            currency: currency,
            rates: rates,
            satisfies: satisfies
        ) { amount in
            calls.amounts.append(amount)
            try await saving?(amount)
        }
    }

    // MARK: - Seeding -

    @Test("The keypad opens on the minimum it replaces, restated in the entry currency")
    func seedsFromCurrent() {
        #expect(makeModel().enteredAmount == "5")
        #expect(makeModel(currency: .cad).enteredAmount == "6.25")
        #expect(makeModel(role: .chat, speaker: .usd(8)).enteredAmount == "8")
    }

    @Test("With no chat minimum of its own, the Chat keypad opens empty, not on the join minimum")
    func chatSeedsEmptyWithoutSpeaker() {
        #expect(makeModel(role: .chat).enteredAmount == "")
    }

    // MARK: - Save gating -

    @Test("Save is shut while empty, zero, or below the minimum transfer value")
    func canSaveNeedsATransferableAmount() {
        let model = makeModel()
        for entry in ["", "0", "0.001"] {
            model.enteredAmount = entry
            #expect(!model.canSave, "\(entry)")
        }
        model.enteredAmount = "0.01"
        #expect(model.canSave)
    }

    @Test("An amount that rounds to nothing in the join minimum's currency can't be saved")
    func belowOneYen() {
        // 0.001 USD is 0.15 JPY, under the yen's minimum transfer value of 1.
        let model = makeModel(join: FiatAmount(value: 500, currency: .jpy))
        model.enteredAmount = "0.001"
        #expect(model.amount == nil)
        model.enteredAmount = "0.01"
        #expect(model.amount == FiatAmount(value: 2, currency: .jpy))
    }

    @Test("An entry that rounds to the current minimum is a no-op, so Save stays shut")
    func unchangedIsNoOp() {
        let model = makeModel(currency: .cad)
        model.enteredAmount = "6.25"
        #expect(!model.canSave)

        let chat = makeModel(role: .chat, speaker: .usd(8))
        chat.enteredAmount = "8"
        #expect(!chat.canSave)
    }

    // MARK: - Currency -

    @Test("The entry is saved in the join minimum's currency, which needn't be USD")
    func savesInJoinCurrency() async {
        let calls = Calls()
        let model = makeModel(join: FiatAmount(value: 500, currency: .jpy), calls: calls)
        model.enteredAmount = "10"

        await model.save()

        #expect(calls.amounts == [FiatAmount(value: 1500, currency: .jpy)])
        #expect(model.state == .saved)
    }

    @Test("A chat minimum entered in another currency is saved in the join minimum's")
    func chatSavesInJoinCurrency() async {
        let calls = Calls()
        let model = makeModel(role: .chat, currency: .cad, calls: calls)
        model.enteredAmount = "12.50"

        await model.save()

        #expect(calls.amounts == [.usd(10)])
    }

    // MARK: - Speaker above listener -

    @Test("A chat minimum at or below the join minimum is blocked before sending, naming the join minimum")
    func chatAtOrBelowJoinIsBlocked() async {
        let calls = Calls()
        let model = makeModel(role: .chat, currency: .cad, calls: calls)

        model.enteredAmount = "6.25"
        #expect(model.blocker == .chatNotAboveJoin(join: FiatAmount(value: 6.25, currency: .cad)))
        model.enteredAmount = "5"
        #expect(model.blocker == .chatNotAboveJoin(join: FiatAmount(value: 6.25, currency: .cad)))

        await model.save()
        #expect(calls.amounts.isEmpty)
        #expect(model.failure == .chatNotAboveJoin(join: FiatAmount(value: 6.25, currency: .cad)))
    }

    @Test("A chat minimum one smallest unit above the join minimum goes through")
    func chatOneCentAboveJoin() {
        let model = makeModel(role: .chat)
        model.enteredAmount = "5.01"
        #expect(model.blocker == nil)
    }

    @Test("A join minimum at or above the chat minimum is blocked before sending")
    func joinAtOrAboveChatIsBlocked() async {
        let calls = Calls()
        let model = makeModel(speaker: .usd(8), calls: calls)

        model.enteredAmount = "8"
        #expect(model.blocker == .invalidRules)
        model.enteredAmount = "7.99"
        #expect(model.blocker == nil)

        model.enteredAmount = "9"
        await model.save()
        #expect(calls.amounts.isEmpty)
        #expect(model.failure == .invalidRules)
    }

    // MARK: - Removing the chat minimum -

    @Test("The chat minimum can be removed, and only when the group sets one")
    func removesChatMinimum() async {
        #expect(!makeModel(role: .chat).canRemove)
        #expect(!makeModel(role: .join, speaker: .usd(8)).canRemove)

        let calls = Calls()
        let model = makeModel(role: .chat, speaker: .usd(8), calls: calls)
        #expect(model.canRemove)

        await model.remove()

        #expect(calls.amounts == [nil])
        #expect(model.state == .saved)
    }

    // MARK: - Creator -

    @Test("A minimum the creator doesn't meet is blocked before sending, speaker rule included")
    func creatorMustSatisfy() async {
        var checked: [ConversationRules] = []
        let calls = Calls()
        let model = makeModel(role: .chat, satisfies: { rules in
            checked.append(rules)
            return false
        }, calls: calls)
        model.enteredAmount = "20"

        await model.save()

        #expect(calls.amounts.isEmpty)
        #expect(model.failure == .rulesNotSatisfied)
        let speaker = MinimumBalanceRequirement(amount: .usd(20), mints: [token])
        #expect(checked.last?.speaker == [.minimumBalance(speaker)])
        #expect(checked.last?.listener == [.minimumBalance(MinimumBalanceRequirement(amount: .usd(5), mints: [token]))])
    }

    @Test("When the creator's balance can't be weighed, the server decides")
    func unknownBalanceSends() async {
        let calls = Calls()
        let model = makeModel(satisfies: { _ in nil }, calls: calls)
        model.enteredAmount = "20"

        await model.save()

        #expect(calls.amounts == [.usd(20)])
    }

    // MARK: - Server refusals -

    @Test("The server's rule refusals surface as their own alerts and leave Save open")
    func serverRefusals() async {
        for (error, failure) in [
            (ErrorEditChat.invalidRules, EditGroupBalanceRequirementModel.Failure.invalidRules),
            (ErrorEditChat.rulesNotSatisfied, .rulesNotSatisfied),
        ] {
            let model = makeModel(saving: { _ in throw error })
            model.enteredAmount = "3"

            await model.save()

            #expect(model.failure == failure)
            #expect(model.state == .normal)
            #expect(model.canSave)
        }
    }

    @Test("Any other failure surfaces as failed")
    func otherFailure() async {
        let model = makeModel(saving: { _ in throw Boom() })
        model.enteredAmount = "3"

        await model.save()

        #expect(model.failure == .failed)
        #expect(model.state == .normal)
    }
}
