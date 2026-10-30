//
//  GroupKeyEnvelopeStoreTests.swift
//  FlipcashCoreTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
import FlipcashAPI

@testable import FlipcashCore

/// SharedCore exports its own `KeyPair`; these tests mean the app's.
private typealias KeyPair = FlipcashCore.KeyPair

@Suite("GroupKeyEnvelopes storage")
struct GroupKeyEnvelopeStoreTests {

    private struct Offline: Error {}

    private final class MemoryStore: GroupKeyEnvelopeStore, @unchecked Sendable {
        private let lock = NSLock()
        private var rows: [ConversationID: Data] = [:]
        var failsToStore = false

        func material(for conversationID: ConversationID) throws -> GroupKeyMaterial? {
            lock.withLock { rows[conversationID] }.flatMap { GroupKeyMaterial(serialized: $0) }
        }
        func store(_ material: GroupKeyMaterial, for conversationID: ConversationID) throws {
            if failsToStore { throw Offline() }
            let bytes = try material.serialized()
            lock.withLock { rows[conversationID] = bytes }
        }
        func remove(for conversationID: ConversationID) throws {
            lock.withLock { rows[conversationID] = nil }
        }
        func bytes(_ conversationID: ConversationID) -> Data? { lock.withLock { rows[conversationID] } }
    }

    /// The server's side: what it holds for the viewer, what it accepts, and how often it is asked.
    private final class Server: @unchecked Sendable {
        private let lock = NSLock()
        private var _material: GroupKeyMaterial?
        private var _gets = 0
        private var _sets = 0
        var offline = false
        var setError: Error?

        init(_ material: GroupKeyMaterial? = nil) { _material = material }

        var material: GroupKeyMaterial? { lock.withLock { _material } }
        var gets: Int { lock.withLock { _gets } }
        var sets: Int { lock.withLock { _sets } }

        func get() throws -> GroupKeyMaterial {
            try lock.withLock {
                _gets += 1
                if offline { throw Offline() }
                guard let _material else { throw ErrorGetKeyEnvelope.noEnvelope }
                return _material
            }
        }
        func set(_ envelope: ConversationKeyEnvelope, selfID: UserID) throws {
            try lock.withLock {
                _sets += 1
                if let setError { throw setError }
                _material = .own(envelope: envelope, wrappedBy: selfID)
            }
        }
    }

    /// Real crypto for envelopes; an invite copy opens to its key envelope's ciphertext, as the
    /// other suite's fake does, because a real bundle needs the inviter's secret.
    private struct InviteFakingSealer: GroupKeySealing {
        let real = SharedCoreGroupKeySealer()
        func newGroupKey() -> Data { real.newGroupKey() }
        func wrap(groupKey: Data, owner: KeyPair, recipient: PublicKey, conversationID: ConversationID) throws -> ConversationKeyEnvelope {
            try real.wrap(groupKey: groupKey, owner: owner, recipient: recipient, conversationID: conversationID)
        }
        func unwrap(_ envelope: ConversationKeyEnvelope, owner: KeyPair, wrapper: PublicKey, conversationID: ConversationID) throws -> Data {
            try real.unwrap(envelope, owner: owner, wrapper: wrapper, conversationID: conversationID)
        }
        func open(_ bundle: InviteKeyBundle, owner: KeyPair, creatorPublicKey: PublicKey, wrappedByCreator: Bool, conversationID: ConversationID) throws -> Data {
            guard wrappedByCreator else { throw GroupKeyUnusable(failsAt: .wrappedBy) }
            return bundle.keyEnvelope.ciphertext
        }
    }

    private let sealer = InviteFakingSealer()
    private let owner = KeyPair.generate()!
    private let creator = KeyPair.generate()!
    private let selfID = UUID()
    private let creatorID = UUID()
    private let chat = ConversationID(data: Data(repeating: 3, count: 32))
    private let groupKey = Data((0..<32).map { UInt8(200 - $0) })

    private func envelopes(_ server: Server, _ store: MemoryStore?, opensInviteBundles: Bool = true) -> GroupKeyEnvelopes {
        GroupKeyEnvelopes(
            sealer: sealer,
            owner: owner,
            selfUserID: selfID,
            setEnvelope: { [selfID] _, envelope in try server.set(envelope, selfID: selfID) },
            getEnvelope: { _ in try server.get() },
            resolveKey: { [creatorID, creator] userID in
                guard userID == creatorID else { throw ErrorGetKeyEnvelope.notFound }
                return creator.publicKey
            },
            opensInviteBundles: opensInviteBundles,
            envelopeStore: store
        )
    }

    private func selfWrapped(_ key: Data? = nil) throws -> GroupKeyMaterial {
        .own(envelope: try sealer.wrap(groupKey: key ?? groupKey, owner: owner, recipient: owner.publicKey, conversationID: chat), wrappedBy: selfID)
    }

    private func creatorWrapped() throws -> GroupKeyMaterial {
        .own(envelope: try sealer.wrap(groupKey: groupKey, owner: creator, recipient: owner.publicKey, conversationID: chat), wrappedBy: creatorID)
    }

    private func stranger() throws -> GroupKeyMaterial {
        let other = KeyPair.generate()!
        return .own(envelope: try sealer.wrap(groupKey: groupKey, owner: other, recipient: owner.publicKey, conversationID: chat), wrappedBy: UUID())
    }

    private func envelope(of material: GroupKeyMaterial?) -> ConversationKeyEnvelope? {
        guard case .own(let envelope, _) = material else { return nil }
        return envelope
    }

    // MARK: - Read -

    @Test("A stored envelope opens after a restart with the network down, without a fetch")
    func opensOfflineAfterRestart() async throws {
        let server = Server(try selfWrapped())
        let store = MemoryStore()
        #expect(try await envelopes(server, store).groupKey(for: chat, creator: creatorID) == groupKey)
        #expect(server.gets == 1)

        server.offline = true
        let restarted = envelopes(server, store)
        #expect(try await restarted.groupKey(for: chat, creator: creatorID) == groupKey)
        #expect(server.gets == 1)
    }

    @Test("A stored envelope that fails to unwrap falls back to the network and is replaced")
    func badStoredFallsBack() async throws {
        let server = Server(try selfWrapped())
        let store = MemoryStore()
        try store.store(try stranger(), for: chat)

        #expect(try await envelopes(server, store).groupKey(for: chat, creator: creatorID) == groupKey)
        #expect(server.gets == 1)
        #expect(try store.material(for: chat) == server.material)
    }

    @Test("Without a store, nothing is kept and every launch fetches")
    func noStore() async throws {
        let server = Server(try selfWrapped())
        _ = try await envelopes(server, nil).groupKey(for: chat, creator: creatorID)
        _ = try await envelopes(server, nil).groupKey(for: chat, creator: creatorID)
        #expect(server.gets == 2)
    }

    // MARK: - Write -

    @Test("A fetch stores the envelope exactly as the server returned it")
    func fetchStores() async throws {
        let server = Server(try selfWrapped())
        let store = MemoryStore()
        _ = try await envelopes(server, store).groupKey(for: chat, creator: creatorID)
        #expect(try store.material(for: chat) == server.material)
        #expect(envelope(of: try store.material(for: chat))?.scheme == SharedCoreGroupKeySealer.scheme.rawValue)
    }

    @Test("The unwrapped key is never written")
    func keyNeverWritten() async throws {
        let server = Server(try selfWrapped())
        let store = MemoryStore()
        let sut = envelopes(server, store)
        _ = try await sut.groupKey(for: chat, creator: creatorID)

        let bytes = try #require(store.bytes(chat))
        #expect(bytes.range(of: groupKey) == nil)

        // Nor when the creator generates the key.
        let created = MemoryStore()
        let createdServer = Server()
        let creating = envelopes(createdServer, created)
        try await creating.storeNewKey(for: chat)
        let key = try await creating.groupKey(for: chat, creator: selfID)
        #expect(key.count == 32)
        #expect(try #require(created.bytes(chat)).range(of: key) == nil)
    }

    @Test("A creator's new key stores their own envelope, which opens offline")
    func newKeyStores() async throws {
        let server = Server()
        let store = MemoryStore()
        let creating = envelopes(server, store)
        try await creating.storeNewKey(for: chat)
        #expect(try store.material(for: chat) == server.material)

        server.offline = true
        let key = try await envelopes(server, store).groupKey(for: chat, creator: selfID)
        #expect(key.count == 32)
        #expect(server.gets == 0)
    }

    // MARK: - Invalidation -

    @Test("ALREADY_SET on a new key removes the row, and the stored envelope wins on the next read")
    func alreadySetOnNewKey() async throws {
        let server = Server(try selfWrapped())
        server.setError = ErrorSetKeyEnvelope.alreadySet
        let store = MemoryStore()
        try store.store(try stranger(), for: chat)

        try await envelopes(server, store).storeNewKey(for: chat)
        #expect(store.bytes(chat) == nil)

        #expect(try await envelopes(server, store).groupKey(for: chat, creator: selfID) == groupKey)
        #expect(try store.material(for: chat) == server.material)
    }

    @Test("A wrapper that is neither the viewer nor the creator removes the row")
    func untrustedWrapperRemovesRow() async throws {
        let untrusted = try stranger()
        let server = Server(untrusted)
        let store = MemoryStore()
        try store.store(untrusted, for: chat)

        await #expect(throws: GroupKeyNotSelfWrapped.self) {
            try await envelopes(server, store).groupKey(for: chat, creator: creatorID)
        }
        #expect(store.bytes(chat) == nil)
    }

    @Test("An untrusted envelope the server returns is not stored")
    func untrustedFetchNotStored() async throws {
        let server = Server(try stranger())
        let store = MemoryStore()
        await #expect(throws: GroupKeyNotSelfWrapped.self) {
            try await envelopes(server, store).groupKey(for: chat, creator: creatorID)
        }
        #expect(store.bytes(chat) == nil)
    }

    @Test("A creator-wrapped envelope is replaced by the member's own once the server takes it")
    func creatorWrapReplacedByOwn() async throws {
        let server = Server(try creatorWrapped())
        let store = MemoryStore()
        try store.store(try creatorWrapped(), for: chat)

        server.offline = false
        #expect(try await envelopes(server, store).groupKey(for: chat, creator: creatorID) == groupKey)
        #expect(server.sets == 1)
        #expect(try store.material(for: chat) == server.material)
        guard case .own(_, let wrappedBy) = try store.material(for: chat) else { Issue.record("not an own envelope"); return }
        #expect(wrappedBy == selfID)

        // Offline from here on: the member's own envelope needs no creator lookup.
        server.offline = true
        #expect(try await envelopes(server, store).groupKey(for: chat, creator: creatorID) == groupKey)
    }

    @Test("A creator-wrapped envelope stays stored when the self-wrap fails")
    func creatorWrapKeptWhenSelfWrapFails() async throws {
        let wrapped = try creatorWrapped()
        let server = Server(wrapped)
        server.setError = Offline()
        let store = MemoryStore()

        #expect(try await envelopes(server, store).groupKey(for: chat, creator: creatorID) == groupKey)
        #expect(try store.material(for: chat) == wrapped)
    }

    @Test("ALREADY_SET on the self-wrap removes the creator-wrapped row")
    func selfWrapAlreadySetRemovesRow() async throws {
        let wrapped = try creatorWrapped()
        let server = Server(wrapped)
        server.setError = ErrorSetKeyEnvelope.alreadySet
        let store = MemoryStore()
        try store.store(wrapped, for: chat)

        #expect(try await envelopes(server, store).groupKey(for: chat, creator: creatorID) == groupKey)
        #expect(store.bytes(chat) == nil)
    }

    @Test("A storage failure leaves no row behind")
    func storageFailureLeavesNoRow() async throws {
        let server = Server(try selfWrapped(Data(repeating: 9, count: 32)))
        let store = MemoryStore()
        try store.store(try stranger(), for: chat)
        store.failsToStore = true

        _ = try await envelopes(server, store).groupKey(for: chat, creator: creatorID)
        #expect(store.bytes(chat) == nil)
    }

    // MARK: - Invite copies -

    private func inviteCopy(wrappedBy: UserID?, wrappedByPublicKey: PublicKey? = nil) throws -> GroupKeyMaterial {
        .invite(
            InviteKeyBundle(
                inviteID: InviteID(data: Data(repeating: 7, count: 32)),
                keyEnvelope: InviteKeyEnvelope(scheme: 1, nonce: Data(), ciphertext: groupKey, signature: Data()),
                secretEnvelope: InviteSecretEnvelope(scheme: 1, nonce: Data(), ciphertext: Data())
            ),
            wrappedBy: wrappedBy,
            wrappedByPublicKey: wrappedByPublicKey
        )
    }

    @Test("An invite copy is replaced by the member's own envelope, and that opens offline")
    func inviteCopyReplacedByOwn() async throws {
        let server = Server(try inviteCopy(wrappedBy: creatorID))
        let store = MemoryStore()

        #expect(try await envelopes(server, store).groupKey(for: chat, creator: creatorID) == groupKey)
        #expect(try store.material(for: chat) == server.material)
        guard case .own = try store.material(for: chat) else { Issue.record("still the invite copy"); return }

        server.offline = true
        #expect(try await envelopes(server, store).groupKey(for: chat, creator: creatorID) == groupKey)
    }

    @Test("An invite copy stays stored while the self-wrap hasn't landed, and opens offline from there")
    func inviteCopyKeptUntilSelfWrap() async throws {
        let copy = try inviteCopy(wrappedBy: creatorID, wrappedByPublicKey: creator.publicKey)
        let server = Server(copy)
        server.setError = Offline()
        let store = MemoryStore()

        #expect(try await envelopes(server, store).groupKey(for: chat, creator: creatorID) == groupKey)
        #expect(try store.material(for: chat) == copy)

        // The sent-along creator key stands in for the lookup that can't run offline.
        let offlineLookup = GroupKeyEnvelopes(
            sealer: sealer, owner: owner, selfUserID: selfID,
            setEnvelope: { _, _ in throw Offline() },
            getEnvelope: { _ in throw Offline() },
            resolveKey: { _ in throw Offline() },
            envelopeStore: store
        )
        #expect(try await offlineLookup.groupKey(for: chat, creator: creatorID) == groupKey)
    }

    @Test("An invite copy that fails a check removes the row and is not stored")
    func unusableInviteCopyRemovesRow() async throws {
        let copy = try inviteCopy(wrappedBy: UUID())
        let server = Server(copy)
        let store = MemoryStore()

        await #expect(throws: GroupKeyUnusable.self) {
            try await envelopes(server, store).groupKey(for: chat, creator: creatorID)
        }
        #expect(store.bytes(chat) == nil)

        try store.store(copy, for: chat)
        await #expect(throws: GroupKeyUnusable.self) {
            try await envelopes(server, store).groupKey(for: chat, creator: creatorID)
        }
        #expect(store.bytes(chat) == nil)
    }

    @Test("A stored invite copy the instance can't open yet is kept")
    func notYetOpenedInviteCopyKept() async throws {
        let copy = try inviteCopy(wrappedBy: creatorID)
        let server = Server(copy)
        let store = MemoryStore()
        try store.store(copy, for: chat)

        await #expect(throws: InviteBundleNotOpened.self) {
            try await envelopes(server, store, opensInviteBundles: false).groupKey(for: chat, creator: creatorID)
        }
        #expect(try store.material(for: chat) == copy)
    }

    // MARK: - Serialization -

    @Test("Material round trips through its serialized form")
    func roundTrip() throws {
        for material in [try selfWrapped(), try creatorWrapped(), try inviteCopy(wrappedBy: creatorID, wrappedByPublicKey: creator.publicKey), try inviteCopy(wrappedBy: nil)] {
            #expect(GroupKeyMaterial(serialized: try material.serialized()) == material)
        }
        #expect(GroupKeyMaterial(serialized: Data([0xFF, 0xFF])) == nil)
    }
}
