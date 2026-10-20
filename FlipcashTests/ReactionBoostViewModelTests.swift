//
//  ReactionBoostViewModelTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("ReactionBoostViewModel")
struct ReactionBoostViewModelTests {

    private let author = UUID()
    private let host = UUID()

    // MARK: - Intent selection

    @Test("A member boosting another member's message pays author and host 80/20 in one intent")
    func twoPayeesUseOneMultiTransfer() async throws {
        let (viewModel, payments, reactions) = try await make(sender: author, creator: host, cents: 1000)

        #expect(await viewModel.submit() == .success)

        #expect(payments.singleSends.isEmpty)
        let multi = try #require(payments.multiSends.first)
        #expect(payments.multiSends.count == 1)
        #expect(multi.map(\.amount.nativeAmount.value) == [8, 2])
        #expect(multi.map(\.recipientOwner) == [payments.key(for: author), payments.key(for: host)])
        #expect(viewModel.splitDescription.hasPrefix("80%"))
        #expect(reactions.calls == [.add, .record(1000)])
    }

    @Test("Boosting the host's own message pays the whole amount to the host")
    func hostsMessageIsOnePayee() async throws {
        let (viewModel, payments, _) = try await make(sender: host, creator: host, cents: 500)

        #expect(await viewModel.submit() == .success)

        #expect(payments.multiSends.isEmpty)
        #expect(payments.singleSends.map(\.amount.nativeAmount.value) == [5])
        #expect(payments.singleSends.map(\.recipientOwner) == [payments.key(for: host)])
    }

    @Test("The host boosting a member's message pays the whole amount to the author")
    func hostPayingIsOnePayee() async throws {
        let container = try await SendAmountViewModelTests.makeReadyToSendContainer()
        let (viewModel, payments, _) = try await make(
            container: container,
            sender: author,
            creator: container.session.userID,
            cents: 500
        )

        #expect(await viewModel.submit() == .success)

        #expect(payments.multiSends.isEmpty)
        #expect(payments.singleSends.map(\.recipientOwner) == [payments.key(for: author)])
        #expect(viewModel.splitDescription == "100% goes to the person who wrote the message")
    }

    @Test("A boost on your own message can't be submitted")
    func selfBoostIsRefused() async throws {
        let container = try await SendAmountViewModelTests.makeReadyToSendContainer()
        let (viewModel, payments, reactions) = try await make(
            container: container,
            sender: container.session.userID,
            creator: host,
            cents: 500
        )

        #expect(!viewModel.canSubmit)
        #expect(await viewModel.submit() == .failed)
        #expect(payments.singleSends.isEmpty && payments.multiSends.isEmpty)
        #expect(reactions.calls.isEmpty)
    }

    @Test("Two payees need the fixture's 3¢ minimum")
    func twoPayeeMinimum() async throws {
        let (viewModel, payments, reactions) = try await make(sender: author, creator: host, cents: 2)

        #expect(viewModel.minimumCents == 3)
        #expect(!viewModel.canSubmit)
        #expect(await viewModel.submit() == .failed)
        #expect(payments.multiSends.isEmpty)
        #expect(reactions.calls.isEmpty)
    }

    // MARK: - Add, then pay

    @Test("A failed payment removes the reaction the boost just added")
    func failedPaymentRollsBackAdd() async throws {
        let (viewModel, payments, reactions) = try await make(sender: author, creator: host, cents: 1000)
        payments.failure = URLError(.notConnectedToInternet)

        #expect(await viewModel.submit() == .failed)

        #expect(reactions.calls == [.add, .remove])
    }

    @Test("A failed payment leaves a reaction the user already had")
    func failedPaymentKeepsExistingReaction() async throws {
        let (viewModel, payments, reactions) = try await make(sender: author, creator: host, cents: 1000)
        reactions.addResult = .alreadyReacted
        payments.failure = URLError(.notConnectedToInternet)

        #expect(await viewModel.submit() == .failed)

        #expect(reactions.calls == [.add])
    }

    @Test("A boost on top of an earlier one records the new self total")
    func recordsRunningSelfTotal() async throws {
        let (viewModel, _, reactions) = try await make(sender: author, creator: host, cents: 500)
        reactions.addResult = .alreadyReacted
        reactions.priorSelfCents = 100

        #expect(await viewModel.submit() == .success)

        #expect(reactions.calls == [.add, .record(600)])
    }

    @Test("A failed add never pays")
    func failedAddNeverPays() async throws {
        let (viewModel, payments, reactions) = try await make(sender: author, creator: host, cents: 1000)
        reactions.addResult = .failed

        #expect(await viewModel.submit() == .failed)

        #expect(payments.multiSends.isEmpty && payments.singleSends.isEmpty)
        #expect(reactions.calls == [.add])
    }

    // MARK: - Helpers

    private func make(
        container: SessionContainer? = nil,
        sender: UserID,
        creator: UserID,
        cents: UInt64
    ) async throws -> (ReactionBoostViewModel, FakeBoostPayments, FakeBoostReactions) {
        let container = if let container { container } else { try await SendAmountViewModelTests.makeReadyToSendContainer() }
        let payments = FakeBoostPayments()
        let reactions = FakeBoostReactions()
        let viewModel = ReactionBoostViewModel(
            sessionContainer: container,
            target: ReactionBoostTarget(
                conversationID: .test(1),
                messageID: MessageID(value: 1),
                emoji: "💯",
                messageSender: sender,
                creator: creator
            ),
            sender: payments,
            multiSender: payments,
            resolver: payments,
            reactions: reactions
        )
        #expect(viewModel.selectedBalance != nil)
        viewModel.selectedCents = cents
        return (viewModel, payments, reactions)
    }
}

@MainActor
private final class FakeBoostPayments: DirectSending, MultiSending, RecipientResolving {

    private(set) var singleSends: [(amount: ExchangedFiat, recipientOwner: PublicKey)] = []
    private(set) var multiSends: [[(amount: ExchangedFiat, recipientOwner: PublicKey)]] = []
    var failure: (any Error)?
    private var keys: [UserID: PublicKey] = [:]

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
        if let failure { throw failure }
        singleSends.append((amount, destination))
    }

    func sendMultiple(_ payments: [(amount: ExchangedFiat, recipientOwner: PublicKey)], verifiedState: VerifiedState, chat: ChatPaymentMetadata?) async throws {
        if let failure { throw failure }
        multiSends.append(payments)
    }
}

@MainActor
private final class FakeBoostReactions: ReactionBoostReacting {

    enum Call: Equatable {
        case add
        case remove
        case record(UInt64)
    }

    private(set) var calls: [Call] = []
    var addResult: ConversationReactions.BoostAdd = .added
    var priorSelfCents: UInt64 = 0

    func addForBoost(_ emoji: String, messageID: MessageID, in conversationID: ConversationID, at date: Date) async -> ConversationReactions.BoostAdd {
        calls.append(.add)
        return addResult
    }

    func toggle(_ emoji: String, messageID: MessageID, in conversationID: ConversationID, at date: Date) {
        calls.append(.remove)
    }

    func selfBoostCents(_ emoji: String, messageID: MessageID, in conversationID: ConversationID) -> UInt64 {
        priorSelfCents
    }

    func recordOwnBoost(_ emoji: String, selfTotalCents: UInt64, messageID: MessageID, in conversationID: ConversationID) {
        calls.append(.record(selfTotalCents))
    }
}
