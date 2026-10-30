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

    @Test("An amount over the balance shows the insufficient balance alert instead of moving on")
    func overBalanceIsRefusedOnNext() async throws {
        let (viewModel, _) = try await make(total: "101")

        #expect(viewModel.confirmAmount() == false)
        #expect(viewModel.session.dialogItem?.title == "Insufficient Balance")
    }

    @Test("An amount within the balance moves on to Select People")
    func withinBalanceMovesOn() async throws {
        let (viewModel, _) = try await make(total: "100")

        #expect(viewModel.confirmAmount())
        #expect(viewModel.session.dialogItem == nil)
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
        #expect(viewModel.sendButtonTitle == "Send to 2 People")
    }

    // MARK: - Including yourself

    @Test("You and four on $5.00 pays each of the four $1.00 in one intent and keeps the fifth share")
    func youAndFourPaysFourParts() async throws {
        let (viewModel, payments) = try await make(total: "5")
        let picked = [UUID(), UUID(), UUID(), UUID()]
        viewModel.toggle(viewModel.session.userID)
        picked.forEach(viewModel.toggle)

        #expect(viewModel.sendButtonTitle == "Send to 4 People")
        #expect(viewModel.eachLabel == "$1.00 Each")
        #expect(await viewModel.submit() == .success)

        let multi = try #require(payments.multiSends.first)
        #expect(multi.map(\.amount.nativeAmount.value) == [1, 1, 1, 1])
        #expect(multi.map(\.recipientOwner) == picked.map(payments.key(for:)))
    }

    @Test("You and one on $5.00 is a single payment of half, shown as $2.50 Each")
    func youAndOneIsSingleHalf() async throws {
        let (viewModel, payments) = try await make(total: "5")
        let alice = UUID()
        viewModel.toggle(alice)
        viewModel.toggle(viewModel.session.userID)

        #expect(viewModel.sendButtonTitle == "Send to 1 Person")
        #expect(viewModel.eachLabel == "$2.50 Each")
        #expect(await viewModel.submit() == .success)

        #expect(payments.multiSends.isEmpty)
        #expect(payments.singleSends.map(\.amount.nativeAmount.value) == [Decimal(string: "2.5")])
        #expect(payments.singleSends.map(\.recipientOwner) == [payments.key(for: alice)])
    }

    @Test("Your share is the last one wherever You was checked, so it never takes a leftover cent")
    func yourShareIsLast() async throws {
        let (viewModel, payments) = try await make(total: "1")
        let (a, b) = (UUID(), UUID())
        viewModel.toggle(viewModel.session.userID)
        [a, b].forEach(viewModel.toggle)

        #expect(viewModel.split?.kept == 33)
        #expect(await viewModel.submit() == .success)

        let multi = try #require(payments.multiSends.first)
        #expect(multi.map(\.amount.nativeAmount.value) == [Decimal(string: "0.34"), Decimal(string: "0.33")])
    }

    @Test("You alone can't send: the button stays disabled and the selection can't confirm")
    func youAloneCannotSend() async throws {
        let (viewModel, _) = try await make(total: "1")
        viewModel.toggle(viewModel.session.userID)

        #expect(viewModel.isSelected(viewModel.session.userID))
        #expect(viewModel.selection.isEmpty)
        #expect(viewModel.confirmSelection() == false)
    }

    @Test("You count toward the 10: with You checked a tenth member is refused")
    func youCountTowardTheCapFirst() async throws {
        let (viewModel, _) = try await make(total: "20")
        viewModel.toggle(viewModel.session.userID)
        (0..<9).forEach { _ in viewModel.toggle(UUID()) }
        #expect(viewModel.session.dialogItem == nil)

        viewModel.toggle(UUID())

        #expect(viewModel.selection.count == 9)
        #expect(viewModel.session.dialogItem?.title == "10 People Max")
    }

    @Test("With ten members checked, checking You is refused")
    func youCountTowardTheCapLast() async throws {
        let (viewModel, _) = try await make(total: "20")
        (0..<10).forEach { _ in viewModel.toggle(UUID()) }

        viewModel.toggle(viewModel.session.userID)

        #expect(viewModel.includesSender == false)
        #expect(viewModel.session.dialogItem?.title == "10 People Max")
    }

    @Test("The too-small check counts your share")
    func tooSmallCountsYourShare() async throws {
        let (viewModel, payments) = try await make(total: "0.02")
        viewModel.toggle(viewModel.session.userID)
        [UUID(), UUID()].forEach(viewModel.toggle)

        #expect(viewModel.confirmSelection() == false)
        #expect(viewModel.session.dialogItem?.title == "Amount Too Small")
        #expect(await viewModel.submit() == .failed)
        #expect(payments.multiSends.isEmpty)
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
