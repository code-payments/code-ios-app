//
//  PaymentRequestsLiveUpdateTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("PaymentRequests live updates")
struct PaymentRequestsLiveUpdateTests {

    private let chat = ConversationID.test(1)
    private let creator = UUID()
    private let payer = UUID()
    private let other = UUID()
    private let id = PaymentRequestID(data: Data([1]))
    private let closedDate = Date(timeIntervalSince1970: 1_800_000_000)

    private func request(
        version: UInt64 = 1,
        status: GroupPaymentRequest.Status = .open,
        paid: Bool = false
    ) -> GroupPaymentRequest {
        GroupPaymentRequest(
            id: id,
            creator: creator,
            createdAt: closedDate.addingTimeInterval(-60),
            status: status,
            closedAt: nil,
            version: version,
            chatID: chat,
            split: .init(
                text: .plaintext(title: "Dinner", description: ""),
                currency: "usd",
                endsAt: closedDate.addingTimeInterval(86_400),
                shares: [
                    .init(userID: creator, nativeAmount: 10, settlement: .creator),
                    .init(userID: payer, nativeAmount: 10, settlement: paid ? .manual : nil),
                    .init(userID: other, nativeAmount: 10),
                ]
            )
        )
    }

    private func paidShare(_ user: UUID) -> GroupPaymentRequest.Share {
        .init(userID: user, nativeAmount: 10, paidAt: closedDate, settlement: .intent(Data([9])))
    }

    private func updates(_ version: UInt64, _ list: [DecodedPaymentRequestUpdate.Change.Update]) -> DecodedPaymentRequestUpdate {
        .init(id: id, change: .updates(version: version, list))
    }

    private func store(holding held: GroupPaymentRequest? = nil) -> PaymentRequests {
        let store = PaymentRequests(getChatPage: { _, _, _ in [] }, getRequest: { _ in throw ErrorGetPaymentRequest.unknown })
        if let held { store.ingest([held]) }
        return store
    }

    // MARK: created

    @Test("created with a greater version replaces the held copy")
    func createdGreater() {
        let store = store(holding: request(version: 1))
        let refetch = store.apply([.init(id: id, change: .created(request(version: 3, status: .closed)))])
        #expect(refetch.isEmpty)
        #expect(store.request(id)?.version == 3)
        #expect(store.request(id)?.status == .closed)
    }

    @Test("created with a lesser version keeps the held copy")
    func createdLesser() {
        let store = store(holding: request(version: 3, status: .closed))
        store.apply([.init(id: id, change: .created(request(version: 1)))])
        #expect(store.request(id)?.version == 3)
    }

    @Test("created at an equal version keeps EXPIRED over OPEN")
    func createdEqualExpired() {
        let store = store(holding: request(version: 2, status: .expired))
        store.apply([.init(id: id, change: .created(request(version: 2, status: .open)))])
        #expect(store.request(id)?.status == .expired)
    }

    @Test("created with no held copy stores it")
    func createdNoCopy() {
        let store = store()
        store.apply([.init(id: id, change: .created(request(version: 1)))])
        #expect(store.request(id) != nil)
    }

    // MARK: updates

    @Test("V <= L is ignored, at equal and lesser versions")
    func staleIgnored() {
        let store = store(holding: request(version: 3))
        let refetch = store.apply([
            updates(3, [.sharePaid(paidShare(payer))]),
            updates(2, [.sharePaid(paidShare(payer))]),
        ])
        #expect(refetch.isEmpty)
        #expect(store.request(id)?.version == 3)
        #expect(store.request(id)?.share(for: payer)?.isPaid == false)
    }

    @Test("V == L + 1 applies every change in order and sets the version")
    func nextVersionApplies() {
        let store = store(holding: request(version: 1))
        let refetch = store.apply([updates(2, [
            .sharePaid(paidShare(payer)),
            .sharePaid(paidShare(other)),
            .statusChanged(.completed, closedAt: closedDate),
        ])])
        #expect(refetch.isEmpty)
        let applied = store.request(id)
        #expect(applied?.version == 2)
        #expect(applied?.share(for: payer)?.settlement == .intent(Data([9])))
        #expect(applied?.share(for: other)?.isPaid == true)
        #expect(applied?.status == .completed)
        #expect(applied?.closedAt == closedDate)
    }

    @Test("sharePaid replaces the share with the same user and leaves the others")
    func sharePaidReplaces() {
        let store = store(holding: request(version: 1))
        store.apply([updates(2, [.sharePaid(paidShare(payer))])])
        let applied = store.request(id)
        #expect(applied?.share(for: payer)?.paidAt == closedDate)
        #expect(applied?.share(for: other)?.isPaid == false)
        #expect(applied?.split?.shares.count == 3)
        #expect(applied?.status == .open)
    }

    @Test("a close sets CLOSED and closedAt")
    func closeApplies() {
        let store = store(holding: request(version: 1))
        store.apply([updates(2, [.statusChanged(.closed, closedAt: closedDate)])])
        #expect(store.request(id)?.status == .closed)
        #expect(store.request(id)?.closedAt == closedDate)
    }

    @Test("a status update with no closedAt keeps the held closedAt")
    func statusKeepsClosedAt() {
        let held = GroupPaymentRequest(
            id: id, creator: creator, createdAt: nil, status: .open, closedAt: closedDate,
            version: 1, chatID: chat, split: request().split
        )
        let store = store(holding: held)
        store.apply([updates(2, [.statusChanged(.closed, closedAt: nil)])])
        #expect(store.request(id)?.status == .closed)
        #expect(store.request(id)?.closedAt == closedDate)
    }

    @Test("V > L + 1 refetches and leaves the copy as held")
    func gapRefetches() {
        let store = store(holding: request(version: 1))
        let refetch = store.apply([updates(3, [.sharePaid(paidShare(payer))])])
        #expect(refetch == [id])
        #expect(store.request(id)?.version == 1)
        #expect(store.request(id)?.share(for: payer)?.isPaid == false)
    }

    @Test("an unknown update applies none of the batch and refetches")
    func unknownRefetches() {
        let store = store(holding: request(version: 1))
        let refetch = store.apply([updates(2, [.sharePaid(paidShare(payer)), .unknown])])
        #expect(refetch == [id])
        #expect(store.request(id)?.version == 1)
        #expect(store.request(id)?.share(for: payer)?.isPaid == false)
    }

    @Test("a share the copy does not have refetches without applying the batch")
    func unknownShareRefetches() {
        let store = store(holding: request(version: 1))
        let refetch = store.apply([updates(2, [.sharePaid(paidShare(UUID()))])])
        #expect(refetch == [id])
        #expect(store.request(id)?.version == 1)
    }

    @Test("a status other than COMPLETED or CLOSED refetches")
    func unsupportedStatusRefetches() {
        let store = store(holding: request(version: 1))
        let refetch = store.apply([updates(2, [.statusChanged(.expired, closedAt: closedDate)])])
        #expect(refetch == [id])
        #expect(store.request(id)?.status == .open)
    }

    @Test("updates with no held copy are ignored and nothing is fetched")
    func noCopyIgnored() {
        let store = store()
        let refetch = store.apply([updates(2, [.sharePaid(paidShare(payer))])])
        #expect(refetch.isEmpty)
        #expect(store.request(id) == nil)
    }

    @Test("the same batch twice, or out of order, converges")
    func duplicateAndOutOfOrder() {
        let store = store(holding: request(version: 1))
        let first = updates(2, [.sharePaid(paidShare(payer))])
        let second = updates(3, [.statusChanged(.closed, closedAt: closedDate)])
        // v3 first is a gap; then v2 applies; then v3 applies; then v2 again is stale.
        #expect(store.apply([second]) == [id])
        #expect(store.apply([first, second, first]).isEmpty)
        #expect(store.request(id)?.version == 3)
        #expect(store.request(id)?.status == .closed)
        #expect(store.request(id)?.share(for: payer)?.isPaid == true)
    }

    @Test("a refetch reads the request and merges the fetched copy")
    func refetchMerges() async {
        let fetched = request(version: 5, status: .closed)
        let store = PaymentRequests(getChatPage: { _, _, _ in [] }, getRequest: { _ in (fetched, nil) })
        store.ingest([request(version: 1)])
        await store.refetch(store.apply([updates(4, [.unknown])]))
        #expect(store.request(id)?.version == 5)
    }
}
