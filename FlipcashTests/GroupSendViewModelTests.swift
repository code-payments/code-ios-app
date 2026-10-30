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

    @Test("Two or more recipients are one multi-recipient intent, leftover cents to the first picked")
    func manyRecipientsAreOneIntent() async throws {
        let (viewModel, payments) = try await make(total: "1")
        let picked = [UUID(), UUID(), UUID()]
        picked.forEach(viewModel.toggle)

        #expect(viewModel.eachLabel == "~$0.33 Each")
        #expect(await viewModel.submit() == .success)

        #expect(payments.singleSends.isEmpty)
        let multi = try #require(payments.multiSends.first)
        #expect(multi.map(\.amount.nativeAmount.value) == [Decimal(string: "0.34"), Decimal(string: "0.33"), Decimal(string: "0.33")])
        #expect(multi.map(\.recipientOwner) == picked.map(payments.key(for:)))
        #expect(payments.groupChatIDs == [Self.groupID])
    }

    @Test("An amount above the selected balance can still move on to Split Between")
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

    @Test("You in the split is never paid: $30.00 between You and 2 others pays $10.00 to each of the 2")
    func youIsDroppedFromPayments() async throws {
        let (viewModel, payments) = try await make(total: "30")
        let (a, b) = (UUID(), UUID())
        [viewModel.session.userID, a, b].forEach(viewModel.toggle)

        #expect(viewModel.payees == [a, b])
        #expect(viewModel.eachLabel == "$10.00 Each, including You")
        #expect(await viewModel.submit() == .success)

        let multi = try #require(payments.multiSends.first)
        #expect(multi.map(\.amount.nativeAmount.value) == [10, 10])
        #expect(multi.map(\.recipientOwner) == [a, b].map(payments.key(for:)))
    }

    @Test("You's part is always last, so $1.00 between You, A and B pays A $0.34 and B $0.33")
    func youTakesTheLastShare() async throws {
        let (viewModel, payments) = try await make(total: "1")
        let (a, b) = (UUID(), UUID())
        [viewModel.session.userID, a, b].forEach(viewModel.toggle)

        #expect(await viewModel.submit() == .success)

        let multi = try #require(payments.multiSends.first)
        #expect(multi.map(\.amount.nativeAmount.value) == [Decimal(string: "0.34"), Decimal(string: "0.33")])
    }

    @Test("You and one other is one single payment of half")
    func youAndOneIsASingleSend() async throws {
        let (viewModel, payments) = try await make(total: "10")
        let a = UUID()
        [viewModel.session.userID, a].forEach(viewModel.toggle)

        #expect(await viewModel.submit() == .success)

        #expect(payments.multiSends.isEmpty)
        #expect(payments.singleSends.map(\.amount.nativeAmount.value) == [5])
        #expect(payments.singleSends.map(\.recipientOwner) == [payments.key(for: a)])
    }

    @Test("With You in the split the each line says so, even for one paid member")
    func eachLineSaysIncludingYou() async throws {
        let (viewModel, _) = try await make(total: "10")
        [viewModel.session.userID, UUID()].forEach(viewModel.toggle)

        #expect(viewModel.includesYou)
        #expect(viewModel.eachLabel == "$5.00 Each, including You")
    }

    @Test("Without You the each line is unchanged")
    func eachLineWithoutYou() async throws {
        let (viewModel, _) = try await make(total: "1")
        [UUID(), UUID(), UUID()].forEach(viewModel.toggle)

        #expect(viewModel.includesYou == false)
        #expect(viewModel.eachLabel == "~$0.33 Each")
    }

    @Test("Only You checked leaves nobody to pay")
    func onlyYouCannotContinue() async throws {
        let (viewModel, payments) = try await make(total: "10")
        viewModel.toggle(viewModel.session.userID)

        #expect(viewModel.payees.isEmpty)
        #expect(viewModel.confirmSelection() == false)
        #expect(await viewModel.submit() == .failed)
        #expect(payments.singleSends.isEmpty)
        #expect(payments.multiSends.isEmpty)
    }

    @Test("The cap counts You: You plus 9 others is the most")
    func capCountsYou() async throws {
        let (viewModel, _) = try await make(total: "20")
        viewModel.toggle(viewModel.session.userID)
        (0..<9).forEach { _ in viewModel.toggle(UUID()) }

        #expect(viewModel.selection.count == 10)
        #expect(viewModel.session.dialogItem == nil)
        #expect(viewModel.confirmSelection())

        viewModel.toggle(UUID())

        #expect(viewModel.selection.count == 10)
        #expect(viewModel.session.dialogItem?.title == "10 People Max")
    }

    @Test("The too-small check counts You: $0.02 between You and 2 others is refused")
    func tooSmallCountsYou() async throws {
        let (viewModel, _) = try await make(total: "0.02")
        [viewModel.session.userID, UUID(), UUID()].forEach(viewModel.toggle)

        #expect(viewModel.confirmSelection() == false)
        #expect(viewModel.session.dialogItem?.title == "Amount Too Small")
    }

    @Test("Funds are checked against what the sender pays, not the entered total")
    func fundsCheckUsesThePaidParts() async throws {
        let (viewModel, payments) = try await make(total: "150")
        [viewModel.session.userID, UUID()].forEach(viewModel.toggle)

        #expect(await viewModel.submit() == .success)

        #expect(payments.singleSends.map(\.amount.nativeAmount.value) == [75])
    }

    @Test("A total under one cent each is refused before anything is sent")
    func tooSmallToSplitIsRefused() async throws {
        let (viewModel, payments) = try await make(total: "0.02")
        [UUID(), UUID(), UUID()].forEach(viewModel.toggle)

        #expect(viewModel.confirmSelection() == false)
        #expect(viewModel.session.dialogItem != nil)
        #expect(await viewModel.submit() == .failed)
        #expect(payments.singleSends.isEmpty)
        #expect(payments.multiSends.isEmpty)
    }

    @Test("An eleventh pick is refused and shows the 10 People Max notice")
    func eleventhPickIsRefused() async throws {
        let (viewModel, _) = try await make(total: "20")
        (0..<10).forEach { _ in viewModel.toggle(UUID()) }
        #expect(viewModel.session.dialogItem == nil)

        viewModel.toggle(UUID())

        #expect(viewModel.selection.count == 10)
        #expect(viewModel.session.dialogItem?.title == "10 People Max")
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
