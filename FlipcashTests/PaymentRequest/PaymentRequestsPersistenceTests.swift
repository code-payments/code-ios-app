//
//  PaymentRequestsPersistenceTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Testing
@testable import FlipcashCore
import FlipcashStore
@testable import Flipcash

private let chat = ConversationID.test(1)
private let creator = UUID()
private let payer = UUID()
private let requestID = PaymentRequestID(data: Data([1]))
private let base = Date(timeIntervalSince1970: 1_800_000_000)

private func request(
    version: UInt64 = 1,
    status: GroupPaymentRequest.Status = .open,
    text: GroupPaymentRequest.Text = .plaintext(title: "Dinner", description: ""),
    paid: Bool = false
) -> GroupPaymentRequest {
    GroupPaymentRequest(
        id: requestID,
        creator: creator,
        createdAt: base,
        status: status,
        closedAt: nil,
        version: version,
        chatID: chat,
        split: .init(
            text: text,
            currency: "usd",
            endsAt: base.addingTimeInterval(86_400),
            shares: [
                .init(userID: creator, nativeAmount: 10, paidAt: base, settlement: .creator),
                .init(userID: payer, nativeAmount: 10, paidAt: paid ? base : nil, settlement: paid ? .intent(Data(repeating: 9, count: 32)) : nil),
            ]
        )
    )
}

@Suite("Payment request storage")
struct PaymentRequestDatabaseTests {

    @Test("A request with no row is written")
    func noRow() throws {
        let database = Database.mock
        try database.upsertPaymentRequests([request()])
        #expect(try database.paymentRequest(id: requestID) == request())
    }

    @Test("An older version keeps the stored row")
    func older() throws {
        let database = Database.mock
        try database.upsertPaymentRequests([request(version: 3, status: .closed)])
        try database.upsertPaymentRequests([request(version: 2)])
        #expect(try database.paymentRequest(id: requestID)?.version == 3)
        #expect(try database.paymentRequest(id: requestID)?.status == .closed)
    }

    @Test("A newer version replaces the stored row")
    func newer() throws {
        let database = Database.mock
        try database.upsertPaymentRequests([request(version: 1)])
        try database.upsertPaymentRequests([request(version: 2, paid: true)])
        #expect(try database.paymentRequest(id: requestID) == request(version: 2, paid: true))
    }

    @Test("At an equal version EXPIRED replaces OPEN")
    func expiredOverOpen() throws {
        let database = Database.mock
        try database.upsertPaymentRequests([request(version: 2, status: .open)])
        try database.upsertPaymentRequests([request(version: 2, status: .expired)])
        #expect(try database.paymentRequest(id: requestID)?.status == .expired)
    }

    @Test("At an equal version OPEN does not replace EXPIRED")
    func openKeepsExpired() throws {
        let database = Database.mock
        try database.upsertPaymentRequests([request(version: 2, status: .expired)])
        try database.upsertPaymentRequests([request(version: 2, status: .open)])
        #expect(try database.paymentRequest(id: requestID)?.status == .expired)
    }

    @Test("Requests read back by chat")
    func byChat() throws {
        let database = Database.mock
        try database.upsertPaymentRequests([request()])
        #expect(try database.paymentRequests(in: chat).count == 1)
        #expect(try database.paymentRequests(in: .test(2)).isEmpty)
    }

    @Test("The metadata blob round trips, paid shares and plaintext included")
    func roundTrip() throws {
        let original = request(version: 4, status: .completed, paid: true)
        #expect(GroupPaymentRequest(serializedMetadata: try original.serializedMetadata()) == original)
    }

    @Test("Encrypted text stays sealed through storage")
    func sealedStaysSealed() throws {
        let sealed = GroupPaymentRequest.Text.encrypted(scheme: 1, nonce: Data(repeating: 3, count: 24), ciphertext: Data(repeating: 5, count: 40))
        let database = Database.mock
        try database.upsertPaymentRequests([request(text: sealed)])
        let stored = try #require(try database.paymentRequest(id: requestID))
        #expect(stored.split?.text == sealed)
    }
}

@MainActor
@Suite("Payment requests persistence")
struct PaymentRequestsPersistenceTests {

    private func store(
        _ database: Database,
        chatPage: @escaping PaymentRequests.GetChatPage = { _, _, _ in throw ErrorGetChatPaymentRequests.unknown },
        getRequest: @escaping PaymentRequests.GetRequest = { _ in throw ErrorGetPaymentRequest.unknown }
    ) -> PaymentRequests {
        PaymentRequests(getChatPage: chatPage, getRequest: getRequest, database: database)
    }

    @Test("Ingested copies are written through")
    func ingestWrites() throws {
        let database = Database.mock
        store(database).ingest([request(version: 2)])
        #expect(try database.paymentRequest(id: requestID)?.version == 2)
    }

    @Test("A restart hydrates a chat's requests while offline")
    func hydrateOffline() async throws {
        let database = Database.mock
        store(database).ingest([request(version: 2)])

        let restarted = store(database)
        #expect(restarted.request(requestID) == nil)
        await restarted.refreshChat(chat)
        #expect(restarted.request(requestID)?.version == 2)
    }

    @Test("A restart hydrates one request by id when the read fails")
    func hydrateByID() async throws {
        let database = Database.mock
        store(database).ingest([request(version: 2)])

        let restarted = store(database)
        await restarted.fetchIfMissing(requestID)
        #expect(restarted.request(requestID)?.version == 2)
    }

    @Test("An applied update is written whole at its new version")
    func appliedWrites() throws {
        let database = Database.mock
        let store = store(database)
        store.ingest([request(version: 1)])
        let share = GroupPaymentRequest.Share(userID: payer, nativeAmount: 10, paidAt: base, settlement: .manual)
        store.apply([.init(id: requestID, change: .updates(version: 2, [.sharePaid(share)]))])

        let stored = try #require(try database.paymentRequest(id: requestID))
        #expect(stored.version == 2)
        #expect(stored.split?.shares.last?.settlement == .manual)
    }

    @Test("A stale update writes nothing")
    func staleWritesNothing() throws {
        let database = Database.mock
        let store = store(database)
        store.ingest([request(version: 2)])
        let before = try database.paymentRequest(id: requestID)
        store.apply([.init(id: requestID, change: .updates(version: 2, [.statusChanged(.closed, closedAt: base)]))])
        #expect(try database.paymentRequest(id: requestID) == before)
    }

    @Test("A write-through never overwrites a newer stored row")
    func staleIngestKeepsNewer() throws {
        let database = Database.mock
        try database.upsertPaymentRequests([request(version: 5, status: .closed)])
        store(database).ingest([request(version: 3)])
        #expect(try database.paymentRequest(id: requestID)?.version == 5)
    }
}
