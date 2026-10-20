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
        #expect(reactions.calls == [.record("💯", 1000)])
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

    // MARK: - Boosting an existing reaction

    @Test("A boost pays for the reaction the user already has and never adds one")
    func boostNeverAddsReaction() async throws {
        let (viewModel, payments, reactions) = try await make(sender: author, creator: host, cents: 500)

        #expect(await viewModel.submit() == .success)

        #expect(payments.multiSends.count == 1)
        #expect(reactions.calls == [.record("💯", 500)])
    }

    @Test("A failed payment records nothing and leaves the reaction alone")
    func failedPaymentRecordsNothing() async throws {
        let (viewModel, payments, reactions) = try await make(sender: author, creator: host, cents: 1000)
        payments.failure = URLError(.notConnectedToInternet)

        #expect(await viewModel.submit() == .failed)

        #expect(reactions.calls.isEmpty)
    }

    @Test("A boost on top of an earlier one records the new self total")
    func recordsRunningSelfTotal() async throws {
        let (viewModel, _, reactions) = try await make(sender: author, creator: host, cents: 500)
        reactions.priorSelfCents = 100

        #expect(await viewModel.submit() == .success)

        #expect(reactions.calls == [.record("💯", 600)])
    }

    @Test("The sheet starts on the user's most recent reaction")
    func defaultsToMostRecentReaction() async throws {
        let (viewModel, _, _) = try await make(
            sender: author,
            creator: host,
            cents: 500,
            selfReactions: [Self.reaction("👍", at: 100), Self.reaction("🔥", at: 300), Self.reaction("💯", at: 200)]
        )

        #expect(viewModel.emoji == "🔥")
        #expect(viewModel.canCycleEmoji)
    }

    @Test("Tapping the emoji cycles through the user's reactions, newest to oldest, and the boost follows")
    func cyclesReactions() async throws {
        let (viewModel, _, reactions) = try await make(
            sender: author,
            creator: host,
            cents: 500,
            selfReactions: [Self.reaction("👍", at: 100), Self.reaction("🔥", at: 300), Self.reaction("💯", at: 200)]
        )

        viewModel.cycleEmoji()
        #expect(viewModel.emoji == "💯")
        viewModel.cycleEmoji()
        #expect(viewModel.emoji == "👍")
        viewModel.cycleEmoji()
        #expect(viewModel.emoji == "🔥")

        viewModel.cycleEmoji()
        #expect(await viewModel.submit() == .success)
        #expect(reactions.calls == [.record("💯", 500)])
    }

    @Test("One reaction has nothing to cycle to")
    func singleReactionDoesNotCycle() async throws {
        let (viewModel, _, _) = try await make(sender: author, creator: host, cents: 500)

        #expect(!viewModel.canCycleEmoji)
        viewModel.cycleEmoji()
        #expect(viewModel.emoji == "💯")
    }

    @Test("Removing the shown reaction moves to the next, and removing all of them stops the swipe")
    func removedReactionsDropOut() async throws {
        let (viewModel, payments, _) = try await make(
            sender: author,
            creator: host,
            cents: 500,
            selfReactions: [Self.reaction("👍", at: 100), Self.reaction("🔥", at: 300)]
        )

        viewModel.updateSelfReactions([Self.reaction("👍", at: 100)])
        #expect(viewModel.emoji == "👍")
        #expect(viewModel.canSubmit)

        viewModel.updateSelfReactions([])
        #expect(viewModel.emoji == nil)
        #expect(!viewModel.canSubmit)
        #expect(await viewModel.submit() == .failed)
        #expect(payments.multiSends.isEmpty)
    }

    // MARK: - Helpers

    private func make(
        container: SessionContainer? = nil,
        sender: UserID,
        creator: UserID,
        cents: UInt64,
        selfReactions: [SelfReaction] = [ReactionBoostViewModelTests.reaction("💯", at: 100)]
    ) async throws -> (ReactionBoostViewModel, FakeBoostPayments, FakeBoostReactions) {
        let container = if let container { container } else { try await SendAmountViewModelTests.makeReadyToSendContainer() }
        let payments = FakeBoostPayments()
        let reactions = FakeBoostReactions()
        let viewModel = ReactionBoostViewModel(
            sessionContainer: container,
            target: ReactionBoostTarget(
                conversationID: .test(1),
                messageID: MessageID(value: 1),
                messageSender: sender,
                creator: creator
            ),
            selfReactions: selfReactions,
            sender: payments,
            multiSender: payments,
            resolver: payments,
            reactions: reactions
        )
        #expect(viewModel.selectedBalance != nil)
        viewModel.selectedCents = cents
        return (viewModel, payments, reactions)
    }

    private static func reaction(_ emoji: String, at seconds: TimeInterval) -> SelfReaction {
        SelfReaction(emoji: emoji, reactedAt: Date(timeIntervalSince1970: seconds))
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
        case record(String, UInt64)
    }

    private(set) var calls: [Call] = []
    var priorSelfCents: UInt64 = 0

    func selfBoostCents(_ emoji: String, messageID: MessageID, in conversationID: ConversationID) -> UInt64 {
        priorSelfCents
    }

    func recordOwnBoost(_ emoji: String, selfTotalCents: UInt64, messageID: MessageID, in conversationID: ConversationID) {
        calls.append(.record(emoji, selfTotalCents))
    }
}
