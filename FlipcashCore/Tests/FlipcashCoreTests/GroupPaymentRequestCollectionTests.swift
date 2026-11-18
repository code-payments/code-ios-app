//
//  GroupPaymentRequestCollectionTests.swift
//  FlipcashCoreTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
import FlipcashAPI
@testable import FlipcashCore

@Suite("Group payment requests: collections, payers and the 0.28 contract")
struct GroupPaymentRequestCollectionTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let requestID = Data(repeating: 0x07, count: 16)
    private let chat = Data(repeating: 0xAB, count: 32)
    private let creator = UUID()
    private let payer = UUID()

    private func collectionMetadata(
        endsAt: Date?,
        fixed: Double? = 5,
        summary: Flipcash_Paymentrequest_V1_PayerSummary? = nil,
        version: UInt64 = 1
    ) -> Flipcash_Paymentrequest_V1_PaymentRequestMetadata {
        .with {
            $0.paymentRequestID = .with { $0.value = requestID }
            $0.creator = creator.proto
            $0.createdAt = .init(date: now.addingTimeInterval(-60))
            $0.status = .open
            $0.version = version
            $0.groupChat = .with {
                $0.chatID = .with { $0.value = chat }
                $0.collection = .with {
                    $0.plaintext = .with { $0.title = "Gift"; $0.description_p = "For Sam" }
                    $0.currency = "usd"
                    if let endsAt { $0.endsAt = .init(date: endsAt) }
                    if let fixed { $0.fixed = .with { $0.nativeAmount = fixed } }
                }
            }
            if let summary { $0.payerSummary = summary }
        }
    }

    private let summaryProto = Flipcash_Paymentrequest_V1_PayerSummary.with {
        $0.payerCount = 3
        $0.paidCount = 2
        $0.nativeAmountDue = 0
        $0.nativeAmountPaid = 10
    }

    // MARK: - Decode -

    @Test("A collection decodes its text, currency, deadline, fixed amount and payer summary")
    func decodesCollection() throws {
        let endsAt = now.addingTimeInterval(86_400)
        let request = try #require(GroupPaymentRequest(collectionMetadata(endsAt: endsAt, summary: summaryProto)))

        #expect(request.split == nil)
        let collection = try #require(request.collection)
        #expect(collection.text == .plaintext(title: "Gift", description: "For Sam"))
        #expect(collection.currency == "usd")
        #expect(collection.endsAt == endsAt)
        #expect(collection.paymentAmount == .fixed(.init(nativeAmount: 5)))
        #expect(request.endsAt == endsAt)
        #expect(request.chatID == ConversationID(data: chat))
        #expect(request.payerSummary == .init(payerCount: 3, paidCount: 2, nativeAmountDue: 0, nativeAmountPaid: 10))
    }

    @Test("A collection with an amount kind this build doesn't know has no payment amount")
    func unknownAmountKind() throws {
        let request = try #require(GroupPaymentRequest(collectionMetadata(endsAt: nil, fixed: nil)))
        #expect(request.collection?.paymentAmount == nil)
    }

    @Test("A request with no payer summary decodes it as nil")
    func missingSummary() throws {
        let request = try #require(GroupPaymentRequest(collectionMetadata(endsAt: nil)))
        #expect(request.payerSummary == nil)
    }

    @Test("A payer decodes unpaid, paid by intent, and an unset status")
    func decodesPayers() {
        let unpaid = GroupPaymentRequest.Payer(.with {
            $0.userID = payer.proto
            $0.nativeAmountDue = 5
            $0.unpaid = .init()
        })
        #expect(unpaid == .init(userID: payer, nativeAmountDue: 5, nativeAmountPaid: 0, status: .unpaid))
        #expect(!unpaid.isPaid)

        let intent = Data(repeating: 0x42, count: 32)
        let paid = GroupPaymentRequest.Payer(.with {
            $0.userID = payer.proto
            $0.nativeAmountPaid = 5
            $0.paid = .with {
                $0.paidAt = .init(date: now)
                $0.intent = .with { $0.value = intent }
            }
        })
        #expect(paid.status == .paid(paidAt: now, settlement: .intent(intent)))
        #expect(paid.isPaid)

        let unset = GroupPaymentRequest.Payer(.with { $0.userID = payer.proto })
        #expect(unset.status == nil)
        #expect(!unset.isPaid)
    }

    @Test("A fetched request carries the caller's payer when set, and nil when not")
    func fetchedCallerPayer() throws {
        let callerPayer = Flipcash_Paymentrequest_V1_Payer.with {
            $0.userID = payer.proto
            $0.nativeAmountDue = 5
            $0.unpaid = .init()
        }
        let withPayer = try #require(PaymentRequestService.Fetched(.with {
            $0.result = .ok
            $0.paymentRequest = collectionMetadata(endsAt: nil)
            $0.callerPayer = callerPayer
        }))
        #expect(withPayer.callerPayer == .init(userID: payer, nativeAmountDue: 5, nativeAmountPaid: 0, status: .unpaid))
        #expect(withPayer.paymentIntentID == nil)
        #expect(withPayer.request.collection != nil)

        let withoutPayer = try #require(PaymentRequestService.Fetched(.with {
            $0.result = .ok
            $0.paymentRequest = collectionMetadata(endsAt: nil)
        }))
        #expect(withoutPayer.callerPayer == nil)
    }

    @Test("Payer and payer-summary updates decode; one missing what it carries is .unknown")
    func decodesNewUpdateArms() {
        let updates: [Flipcash_Paymentrequest_V1_PaymentRequestUpdate.Update] = [
            .with { $0.payerUpdate = .with { $0.payer = .with { $0.userID = payer.proto; $0.unpaid = .init() } } },
            .with { $0.payerSummaryUpdate = .with { $0.payerSummary = summaryProto } },
            .with { $0.payerUpdate = .init() },
            .with { $0.payerSummaryUpdate = .init() },
        ]
        #expect(updates.map(DecodedPaymentRequestUpdate.Change.Update.init) == [
            .payerChanged(.init(userID: payer, nativeAmountDue: 0, nativeAmountPaid: 0, status: .unpaid)),
            .payerSummaryChanged(.init(payerCount: 3, paidCount: 2, nativeAmountDue: 0, nativeAmountPaid: 10)),
            .unknown,
            .unknown,
        ])
    }

    // MARK: - No deadline -

    @Test("An open collection with no ends_at never expires and sets no expiry timer")
    func noDeadlineNeverExpires() throws {
        let request = try #require(GroupPaymentRequest(collectionMetadata(endsAt: nil)))
        let farFuture = now.addingTimeInterval(10 * 365 * 86_400)

        #expect(request.endsAt == nil)
        #expect(request.effectiveStatus(at: farFuture) == .open)
        #expect(request.deadline(at: farFuture) == .noDeadline)
        #expect(GroupPaymentRequest.nextExpiry(of: [request], after: now) == nil)
        #expect(GroupPaymentRequest.deckOrder([request], at: farFuture).map(\.id) == [request.id])
    }

    @Test("An open collection past its ends_at reads as expired")
    func collectionDeadlinePasses() throws {
        let endsAt = now.addingTimeInterval(60)
        let request = try #require(GroupPaymentRequest(collectionMetadata(endsAt: endsAt)))
        #expect(request.effectiveStatus(at: endsAt.addingTimeInterval(1)) == .expired)
        #expect(GroupPaymentRequest.nextExpiry(of: [request], after: now) == endsAt)
    }

    // MARK: - Live updates -

    @Test("A split's payment batch of share, payer and summary updates applies without a refetch")
    func splitPaymentBatchApplies() throws {
        let unpaidShare = GroupPaymentRequest.Share(userID: payer, nativeAmount: 5)
        let split = GroupPaymentRequest(
            id: PaymentRequestID(data: requestID),
            creator: creator,
            createdAt: now,
            status: .open,
            closedAt: nil,
            version: 4,
            chatID: ConversationID(data: chat),
            split: .init(text: nil, currency: "usd", endsAt: now.addingTimeInterval(86_400), shares: [unpaidShare]),
            payerSummary: .init(payerCount: 1, paidCount: 0, nativeAmountDue: 5, nativeAmountPaid: 0)
        )
        let paidShare = GroupPaymentRequest.Share(userID: payer, nativeAmount: 5, paidAt: now, settlement: .manual)
        let summary = GroupPaymentRequest.PayerSummary(payerCount: 1, paidCount: 1, nativeAmountDue: 5, nativeAmountPaid: 5)

        let outcome = split.applying(version: 5, updates: [
            .sharePaid(paidShare),
            .payerChanged(.init(userID: payer, nativeAmountDue: 5, nativeAmountPaid: 5, status: .paid(paidAt: now, settlement: .manual))),
            .payerSummaryChanged(summary),
        ])

        guard case .applied(let applied) = outcome else {
            Issue.record("expected .applied, got \(outcome)"); return
        }
        #expect(applied.version == 5)
        #expect(applied.split?.shares == [paidShare])
        #expect(applied.payerSummary == summary)
    }

    @Test("A collection's payer and summary updates apply; the summary is replaced and the collection kept")
    func collectionBatchApplies() throws {
        let request = try #require(GroupPaymentRequest(collectionMetadata(endsAt: nil, summary: summaryProto, version: 2)))
        let summary = GroupPaymentRequest.PayerSummary(payerCount: 4, paidCount: 3, nativeAmountDue: 0, nativeAmountPaid: 15)

        let outcome = request.applying(version: 3, updates: [
            .payerChanged(.init(userID: payer, nativeAmountDue: 0, nativeAmountPaid: 5, status: .paid(paidAt: now, settlement: .intent(Data([1]))))),
            .payerSummaryChanged(summary),
        ])

        guard case .applied(let applied) = outcome else {
            Issue.record("expected .applied, got \(outcome)"); return
        }
        #expect(applied.version == 3)
        #expect(applied.payerSummary == summary)
        #expect(applied.collection == request.collection)
        #expect(applied.split == nil)
    }

    @Test("A share update on a collection refetches, since a collection has no shares")
    func shareUpdateOnCollectionRefetches() throws {
        let request = try #require(GroupPaymentRequest(collectionMetadata(endsAt: nil, version: 2)))
        let outcome = request.applying(version: 3, updates: [.sharePaid(.init(userID: payer, nativeAmount: 5, settlement: .manual))])
        #expect(outcome == .refetch)
    }

    @Test("A collection closes through a status update")
    func collectionCloses() throws {
        let request = try #require(GroupPaymentRequest(collectionMetadata(endsAt: nil, version: 2)))
        let outcome = request.applying(version: 3, updates: [.statusChanged(.closed, closedAt: now)])
        guard case .applied(let applied) = outcome else {
            Issue.record("expected .applied, got \(outcome)"); return
        }
        #expect(applied.status == .closed)
        #expect(applied.closedAt == now)
        #expect(applied.collection == request.collection)
    }

    // MARK: - Storage -

    @Test("A collection with a deadline and a payer summary survives the stored round trip", arguments: [true, false])
    func storedRoundTrip(withDeadline: Bool) throws {
        let endsAt: Date? = withDeadline ? now.addingTimeInterval(86_400) : nil
        let request = try #require(GroupPaymentRequest(collectionMetadata(endsAt: endsAt, summary: summaryProto)))

        let restored = try #require(GroupPaymentRequest(serializedMetadata: request.serializedMetadata()))

        #expect(restored == request)
        #expect(restored.collection?.endsAt == endsAt)
        #expect(restored.payerSummary == request.payerSummary)
    }

    // MARK: - Results -

    @Test("CreatePaymentRequest's appended INVALID_AMOUNT maps to .invalidAmount at info level")
    func invalidAmount() {
        let error = ErrorCreatePaymentRequest(.invalidAmount, flaggedCategory: .none)
        #expect(error == .invalidAmount)
        #expect(error.reportingLevel == .info)
        #expect(Flipcash_Paymentrequest_V1_CreatePaymentRequestResponse.Result.invalidAmount.rawValue == 9)
    }

    @Test("GetPaymentIntentId results map by position")
    func paymentIntentIDResults() {
        typealias Result = Flipcash_Paymentrequest_V1_GetPaymentIntentIdResponse.Result
        let pairs: [(Result, ErrorGetPaymentIntentID)] = [
            (.ok, .ok), (.denied, .denied), (.notFound, .notFound),
            (.notOpen, .notOpen), (.notAPayer, .notAPayer), (.alreadyPaid, .alreadyPaid),
        ]
        for (result, expected) in pairs {
            #expect(ErrorGetPaymentIntentID(rawValue: result.rawValue) == expected)
        }
    }

    @Test("GetPayers results map by position")
    func payersResults() {
        typealias Result = Flipcash_Paymentrequest_V1_GetPayersResponse.Result
        let pairs: [(Result, ErrorGetPayers)] = [(.ok, .ok), (.denied, .denied), (.notFound, .notFound)]
        for (result, expected) in pairs {
            #expect(ErrorGetPayers(rawValue: result.rawValue) == expected)
        }
    }
}
