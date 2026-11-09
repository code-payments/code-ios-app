//
//  GroupSendViewModelTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("GroupSendViewModel")
struct GroupSendViewModelTests {

    private static let groupID = ConversationID(data: Data(repeating: 0x0B, count: 32))

    @Test("One recipient is a single payment tagged as a group payment")
    func oneRecipientIsSingleSend() async throws {
        let (viewModel, payments) = try await make(total: "5")
        let alice = UUID()
        viewModel.toggle(alice)

        #expect(await viewModel.submit() == .success)

        #expect(payments.multiSends.isEmpty)
        #expect(payments.singleSends.map(\.amount.nativeAmount.value) == [5])
        #expect(payments.singleSends.map(\.recipientOwner) == [payments.key(for: alice)])
        #expect(payments.groupChatIDs == [Self.groupID])
    }

    @Test("Two or more recipients are one intent, each paid the entered amount in selection order")
    func manyRecipientsAreOneIntent() async throws {
        let (viewModel, payments) = try await make(total: "1")
        let picked = [UUID(), UUID(), UUID()]
        picked.forEach(viewModel.toggle)

        #expect(await viewModel.submit() == .success)

        #expect(payments.singleSends.isEmpty)
        let multi = try #require(payments.multiSends.first)
        #expect(multi.map(\.amount.nativeAmount.value) == [1, 1, 1])
        #expect(multi.map(\.recipientOwner) == picked.map(payments.key(for:)))
        #expect(payments.groupChatIDs == [Self.groupID])
    }

    @Test("The button total is the amount times the people checked")
    func sendTitleIsAmountTimesPeople() async throws {
        let (viewModel, _) = try await make(total: "1.50")
        #expect(viewModel.sendTitle == "Send")
        #expect(viewModel.enteredTotal == nil)

        [UUID(), UUID()].forEach(viewModel.toggle)

        #expect(viewModel.enteredAmountEach?.value == Decimal(string: "1.5"))
        #expect(viewModel.enteredTotal?.value == 3)
        #expect(viewModel.sendTitle == "Send \(try #require(viewModel.enteredTotal).formatted())")
    }

    @Test("The confirm sheet reads \"$1.00\" with \"each\" over \"$3.00 total\", or just the amount for one person")
    func confirmLabels() async throws {
        let (viewModel, _) = try await make(total: "1")
        let a = UUID()
        viewModel.toggle(a)

        #expect(viewModel.eachAmountLabel == "$1.00")
        #expect(viewModel.isSplitAcrossSelection == false)
        #expect(viewModel.totalLabel == nil)

        [UUID(), UUID()].forEach(viewModel.toggle)

        #expect(viewModel.eachAmountLabel == "$1.00")
        #expect(viewModel.isSplitAcrossSelection)
        #expect(viewModel.totalLabel == "$3.00 total")
    }

    @Test("The sender is not in the list or the selection")
    func youIsNotListed() async throws {
        let (viewModel, _) = try await make(total: "1")

        #expect(viewModel.members.contains { $0.userID == viewModel.session.userID } == false)
    }

    @Test("An amount above the selected balance can still move on to Send To")
    func overBalanceCanContinue() async throws {
        let (viewModel, _) = try await make(total: "101")

        #expect(viewModel.canContinue)
        #expect(viewModel.session.dialogItem == nil)
    }

    @Test("No amount, or zero, cannot move on")
    func emptyAmountCannotContinue() async throws {
        let (viewModel, _) = try await make(total: "0")

        #expect(viewModel.canContinue == false)
    }

    @Test("A total above the balance is refused on the confirm sheet with the insufficient balance alert")
    func overBalanceIsRefusedOnSubmit() async throws {
        let (viewModel, payments) = try await make(total: "101")
        viewModel.toggle(UUID())

        #expect(await viewModel.submit() == .failed)

        #expect(viewModel.session.dialogItem?.title == "Insufficient Balance")
        #expect(payments.singleSends.isEmpty)
        #expect(payments.multiSends.isEmpty)
    }

    @Test("The cap is 10 people: the eleventh is refused and the selection stays at 10")
    func capIsTenPeople() async throws {
        let (viewModel, _) = try await make(total: "20")
        (0..<10).forEach { _ in viewModel.toggle(UUID()) }

        #expect(viewModel.selection.count == 10)
        #expect(viewModel.session.dialogItem == nil)

        viewModel.toggle(UUID())

        #expect(viewModel.selection.count == 10)
        #expect(viewModel.session.dialogItem?.title == "10 People Max")
    }

    @Test("An amount too small to price in the picked currency shows the insufficient balance alert, not Couldn't Send")
    func belowMinimumShowsInsufficientBalance() async throws {
        let supply: UInt64 = 10_000 * 10_000_000_000
        let jeffy = MintMetadata.makeLaunchpad(address: .jeffy, supplyFromBonding: supply)
        let container = try SessionContainer.makeTest(holdings: [
            SessionContainer.Holding(mint: .usdf, quarks: 100_000_000),
            SessionContainer.Holding(mint: jeffy, quarks: 1_000_000_000_000),
        ])
        container.ratesController.configureTestRates(balanceCurrency: .usd, rates: [Rate(fx: 1.0, currency: .usd)])
        await container.ratesController.verifiedProtoService.saveRates([.freshRate(currencyCode: "USD", rate: 1.0)])
        let payments = FakeGroupPayments()
        let viewModel = GroupSendViewModel(
            sessionContainer: container,
            conversationID: Self.groupID,
            sender: payments,
            multiSender: payments,
            resolver: payments
        )
        viewModel.selectCurrencyAction(exchangedBalance: ExchangedBalance.makeTest(mint: jeffy.address, quarks: 1_000_000_000_000, supplyQuarks: supply))
        viewModel.enteredAmount = "0.0001"
        viewModel.toggle(UUID())

        #expect(await viewModel.submit() == .failed)

        #expect(viewModel.session.dialogItem?.title == "Insufficient Balance")
        #expect(payments.singleSends.isEmpty)
    }

    @Test("Nobody checked sends nothing")
    func nobodyCheckedFails() async throws {
        let (viewModel, payments) = try await make(total: "10")

        #expect(await viewModel.submit() == .failed)
        #expect(payments.singleSends.isEmpty)
        #expect(payments.multiSends.isEmpty)
    }

    @Test("Funds are checked against the total: $60 each to 2 people is refused with $100 in the balance")
    func fundsCheckUsesTheTotal() async throws {
        let (viewModel, payments) = try await make(total: "60")
        [UUID(), UUID()].forEach(viewModel.toggle)

        #expect(await viewModel.submit() == .failed)

        #expect(viewModel.session.dialogItem?.title == "Insufficient Balance")
        #expect(payments.multiSends.isEmpty)
    }

    @Test("Unchecking a member keeps the others in the order they were picked")
    func uncheckKeepsOrder() async throws {
        let (viewModel, _) = try await make(total: "1")
        let (a, b, c) = (UUID(), UUID(), UUID())
        [a, b, c].forEach(viewModel.toggle)

        viewModel.toggle(b)

        #expect(viewModel.selection == [a, c])
    }

    // MARK: - Helpers

    private func make(total: String) async throws -> (GroupSendViewModel, FakeGroupPayments) {
        let container = try await SendAmountViewModelTests.makeReadyToSendContainer()
        let payments = FakeGroupPayments()
        let viewModel = GroupSendViewModel(
            sessionContainer: container,
            conversationID: Self.groupID,
            sender: payments,
            multiSender: payments,
            resolver: payments
        )
        #expect(viewModel.selectedBalance != nil)
        viewModel.enteredAmount = total
        return (viewModel, payments)
    }
}

@MainActor
private final class FakeGroupPayments: DirectSending, MultiSending, RecipientResolving {

    private(set) var singleSends: [(amount: ExchangedFiat, recipientOwner: PublicKey)] = []
    private(set) var multiSends: [[(amount: ExchangedFiat, recipientOwner: PublicKey)]] = []
    private(set) var chats: [ChatPaymentMetadata?] = []
    private var keys: [UserID: PublicKey] = [:]

    /// The chat of every send tagged as a group payment.
    var groupChatIDs: [ConversationID] {
        chats.compactMap {
            guard case .groupPayment(let chatID) = $0 else { return nil }
            return chatID
        }
    }

    func key(for userID: UserID) -> PublicKey {
        if let key = keys[userID] { return key }
        let key = KeyPair.generate()!.publicKey
        keys[userID] = key
        return key
    }

    func resolveContact(e164: String) async throws -> PublicKey {
        throw URLError(.unsupportedURL)
    }

    func resolveUserID(_ userID: UserID) async throws -> PublicKey {
        key(for: userID)
    }

    func send(amount: ExchangedFiat, verifiedState: VerifiedState, to destination: PublicKey, chat: ChatPaymentMetadata?) async throws {
        singleSends.append((amount, destination))
        chats.append(chat)
    }

    func sendMultiple(_ payments: [(amount: ExchangedFiat, recipientOwner: PublicKey)], verifiedState: VerifiedState, chat: ChatPaymentMetadata?) async throws {
        multiSends.append(payments)
        chats.append(chat)
    }
}
