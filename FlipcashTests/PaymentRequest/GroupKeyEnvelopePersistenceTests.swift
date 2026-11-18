//
//  GroupKeyEnvelopePersistenceTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Testing
@testable import FlipcashCore
import FlipcashStore
@testable import Flipcash

private typealias KeyPair = FlipcashCore.KeyPair

private let chat = ConversationID.test(1)
private let selfID = UUID()
private let sealer = SharedCoreGroupKeySealer()
private let groupKey = Data((0..<32).map { UInt8(100 + $0) })

private func ownEnvelope(for owner: KeyPair) throws -> GroupKeyMaterial {
    .own(envelope: try sealer.wrap(groupKey: groupKey, owner: owner, recipient: owner.publicKey, conversationID: chat), wrappedBy: selfID)
}

private func group(_ id: ConversationID) -> Conversation {
    Conversation(id: id, members: [], lastMessage: nil, lastActivity: Date(timeIntervalSince1970: 100), type: .group, creator: selfID, isPrivate: true)
}

@Suite("Group key envelope storage")
struct DatabaseGroupKeyEnvelopeTests {

    @Test("An envelope reads back as stored, and a later store replaces it")
    func roundTripAndReplace() throws {
        let database = Database.mock
        let owner = KeyPair.generate()!
        let first = try ownEnvelope(for: owner)
        try database.store(first, for: chat)
        #expect(try database.material(for: chat) == first)

        let second = try ownEnvelope(for: KeyPair.generate()!)
        try database.store(second, for: chat)
        #expect(try database.material(for: chat) == second)
        #expect(try database.material(for: .test(2)) == nil)
    }

    @Test("The stored bytes never hold the unwrapped key")
    func storedBytesHoldNoKey() throws {
        let owner = KeyPair.generate()!
        let material = try ownEnvelope(for: owner)
        let bytes = try material.serialized()
        #expect(bytes.range(of: groupKey) == nil)
        guard case .own(let envelope, _) = material else { return }
        #expect(bytes.range(of: envelope.ciphertext) != nil)
    }

    @Test("Removing a row leaves the others")
    func remove() throws {
        let database = Database.mock
        let material = try ownEnvelope(for: KeyPair.generate()!)
        try database.store(material, for: chat)
        try database.store(material, for: .test(2))
        try database.remove(for: chat)
        #expect(try database.material(for: chat) == nil)
        #expect(try database.material(for: .test(2)) == material)
    }

    @Test("Leaving a conversation removes its envelope")
    func deleteConversationClears() throws {
        let database = Database.mock
        try database.upsertConversation(group(chat))
        try database.store(try ownEnvelope(for: KeyPair.generate()!), for: chat)
        try database.deleteConversation(conversationID: chat)
        #expect(try database.material(for: chat) == nil)
    }

    @Test("A group feed that reports a group departed removes its envelope")
    func departedGroupClears() throws {
        let database = Database.mock
        try database.upsertConversation(group(chat))
        try database.store(try ownEnvelope(for: KeyPair.generate()!), for: chat)
        try database.replaceGroupFeed([], departed: [chat])
        #expect(try database.material(for: chat) == nil)
    }

    @Test("A group feed that keeps the group keeps its envelope")
    func keptGroupKeepsEnvelope() throws {
        let database = Database.mock
        let material = try ownEnvelope(for: KeyPair.generate()!)
        try database.store(material, for: chat)
        try database.replaceGroupFeed([group(chat)], departed: [])
        #expect(try database.material(for: chat) == material)
    }
}

@MainActor
@Suite("Payment request text offline")
struct EncryptedPaymentRequestOfflineTests {

    private struct Offline: Error {}

    private let creator = KeyPair.generate()!
    private let copy = PaymentRequestCopy(displayCurrency: .usd, rates: [:])

    /// A keyring over the database's envelope store whose network is down.
    private func keyring(_ database: Database, online server: GroupKeyMaterial?) -> ChatKeyring {
        let envelopes = GroupKeyEnvelopes(
            sealer: sealer,
            owner: creator,
            selfUserID: selfID,
            setEnvelope: { _, _ in throw Offline() },
            getEnvelope: { _ in
                guard let server else { throw Offline() }
                return server
            },
            resolveKey: { _ in throw Offline() },
            envelopeStore: database
        )
        return ChatKeyring(owner: creator, selfUserID: selfID, resolveKey: { _ in throw Offline() }, groupKey: { id, creator in
            try await envelopes.groupKey(for: id, creator: creator)
        })
    }

    private func openingSeal(_ keyring: ChatKeyring) -> PaymentRequests.OpeningSeal {
        { _ in
            switch await keyring.opener(for: group(chat)) {
            case .seal(let seal): seal
            case .awaitingKey, .unsupported, .unusableKey: nil
            }
        }
    }

    private func makeRequest(sealedBy seal: ChatSeal) throws -> GroupPaymentRequest {
        GroupPaymentRequest(
            id: PaymentRequestID(data: Data([1])),
            creator: selfID,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            status: .open,
            closedAt: nil,
            version: 1,
            chatID: chat,
            split: .init(
                text: try seal.sealRequestText(title: "Dinner", description: "Friday"),
                currency: "usd",
                endsAt: Date(timeIntervalSince1970: 1_800_086_400),
                shares: [.init(userID: selfID, nativeAmount: 10, paidAt: Date(timeIntervalSince1970: 1_800_000_000), settlement: .creator)]
            )
        )
    }

    @Test("After a restart with the network down, an encrypted request's text opens from the stored envelope")
    func opensOffline() async throws {
        let database = Database.mock
        let server = try ownEnvelope(for: creator)

        // First launch, online: the seal is fetched and its envelope stored.
        let online = PaymentRequests(getChatPage: { _, _, _ in [] }, getRequest: { _ in throw ErrorGetPaymentRequest.unknown }, openingSeal: openingSeal(keyring(database, online: server)), database: database)
        await online.loadSeal(for: chat)
        let seal = try #require(online.seal(for: chat))
        let request = try makeRequest(sealedBy: seal)
        online.ingest([request])
        if case .card = online.cardState(for: request.id, in: chat, sentBy: selfID, copy: copy, now: Date(timeIntervalSince1970: 1_800_000_100)) {} else {
            Issue.record("the online card did not draw")
        }

        // Restart, offline: a fresh keyring, a fresh store, no server.
        let restarted = PaymentRequests(getChatPage: { _, _, _ in throw ErrorGetChatPaymentRequests.unknown }, getRequest: { _ in throw ErrorGetPaymentRequest.unknown }, openingSeal: openingSeal(keyring(database, online: nil)), database: database)
        await restarted.refreshChat(chat)
        await restarted.loadSeal(for: chat)
        #expect(restarted.text(of: request)?.title == "Dinner")
        #expect(restarted.text(of: request)?.description == "Friday")
        if case .card = restarted.cardState(for: request.id, in: chat, sentBy: selfID, copy: copy, now: Date(timeIntervalSince1970: 1_800_000_100)) {} else {
            Issue.record("the restarted card did not draw")
        }
    }

    @Test("Without a stored envelope the same restart draws the card as loading")
    func loadingWithoutEnvelope() async throws {
        let database = Database.mock
        let server = try ownEnvelope(for: creator)
        let online = keyring(database, online: server)
        let seal = try #require(await openingSeal(online)(chat))
        let request = try makeRequest(sealedBy: seal)

        let fresh = Database.mock
        let restarted = PaymentRequests(getChatPage: { _, _, _ in throw ErrorGetChatPaymentRequests.unknown }, getRequest: { _ in throw ErrorGetPaymentRequest.unknown }, openingSeal: openingSeal(keyring(fresh, online: nil)), database: fresh)
        restarted.ingest([request])
        await restarted.loadSeal(for: chat)
        #expect(restarted.cardState(for: request.id, in: chat, sentBy: selfID, copy: copy, now: Date(timeIntervalSince1970: 1_800_000_100)) == .loading)
    }
}
