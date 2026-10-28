//
//  GroupKeyEnvelopesTests.swift
//  FlipcashCoreTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
@testable import FlipcashCore

@Suite("GroupKeyEnvelopes")
struct GroupKeyEnvelopesTests {

    /// Wraps by tagging the key with who it was wrapped for, so a test can read back which key went
    /// to which recipient without real crypto.
    private struct FakeSealer: GroupKeySealing {
        let keys: Keys
        final class Keys: @unchecked Sendable {
            private let lock = NSLock()
            private var _generated: [Data] = []
            private var _unwrappedBy: [PublicKey] = []
            private var _bundleOpens: [(creatorPublicKey: PublicKey, wrappedByCreator: Bool)] = []
            private var _bundleError: GroupKeyUnusable?
            var generated: [Data] { lock.withLock { _generated } }
            var unwrappedBy: [PublicKey] { lock.withLock { _unwrappedBy } }
            var bundleOpens: [(creatorPublicKey: PublicKey, wrappedByCreator: Bool)] { lock.withLock { _bundleOpens } }
            /// When set, every bundle fails this check.
            var bundleError: GroupKeyUnusable? {
                get { lock.withLock { _bundleError } }
                set { lock.withLock { _bundleError = newValue } }
            }
            func recordUnwrap(by wrapper: PublicKey) { lock.withLock { _unwrappedBy.append(wrapper) } }
            func recordBundleOpen(_ creatorPublicKey: PublicKey, _ wrappedByCreator: Bool) {
                lock.withLock { _bundleOpens.append((creatorPublicKey, wrappedByCreator)) }
            }
            func next() -> Data {
                lock.withLock {
                    let key = Data(repeating: UInt8(_generated.count + 1), count: 32)
                    _generated.append(key)
                    return key
                }
            }
        }

        func newGroupKey() -> Data { keys.next() }

        func wrap(groupKey: Data, owner: KeyPair, recipient: PublicKey, conversationID: ConversationID) throws -> ConversationKeyEnvelope {
            ConversationKeyEnvelope(scheme: 1, nonce: recipient.data, ciphertext: groupKey)
        }

        func unwrap(_ envelope: ConversationKeyEnvelope, owner: KeyPair, wrapper: PublicKey, conversationID: ConversationID) throws -> Data {
            keys.recordUnwrap(by: wrapper)
            return envelope.ciphertext
        }

        /// Opens to the key envelope's ciphertext, failing as shared-core does when the wrapper
        /// isn't the creator.
        func open(_ bundle: InviteKeyBundle, owner: KeyPair, creatorPublicKey: PublicKey, wrappedByCreator: Bool, conversationID: ConversationID) throws -> Data {
            keys.recordBundleOpen(creatorPublicKey, wrappedByCreator)
            if let error = keys.bundleError { throw error }
            guard wrappedByCreator else { throw GroupKeyUnusable(failsAt: .wrappedBy) }
            return bundle.keyEnvelope.ciphertext
        }
    }

    private final class Server: @unchecked Sendable {
        private let lock = NSLock()
        private var _stored: ConversationKeyEnvelope?
        private var _sets = 0
        private var _gets = 0
        var wrappedBy: UserID?
        var setError: Error?
        var getError: Error?
        /// What the server returns for an invite-joined member until they store their own envelope.
        var inviteCopy: GroupKeyMaterial?
        /// Lets a set replace a stored envelope, as the server does for a member's self-wrap.
        var replaces = false

        var stored: ConversationKeyEnvelope? { lock.withLock { _stored } }
        var sets: Int { lock.withLock { _sets } }
        var gets: Int { lock.withLock { _gets } }

        init(stored: ConversationKeyEnvelope? = nil, wrappedBy: UserID? = nil) {
            _stored = stored
            self.wrappedBy = wrappedBy
        }

        func set(_ envelope: ConversationKeyEnvelope) throws {
            try lock.withLock {
                _sets += 1
                if let setError { throw setError }
                if _stored != nil && !replaces { throw ErrorSetKeyEnvelope.alreadySet }
                _stored = envelope
                wrappedBy = nil
            }
        }

        func get() throws -> GroupKeyMaterial {
            try lock.withLock {
                _gets += 1
                if let getError { throw getError }
                guard let _stored else {
                    if let inviteCopy { return inviteCopy }
                    throw ErrorGetKeyEnvelope.noEnvelope
                }
                return .own(envelope: _stored, wrappedBy: wrappedBy)
            }
        }
    }

    private let owner = KeyPair.generate()!
    private let selfUserID = UUID()
    private let chat = ConversationID(data: Data(repeating: 3, count: 32))
    private let keys = FakeSealer.Keys()
    private let creatorID = UUID()
    private let creatorKey = KeyPair.generate()!.publicKey

    private func envelopes(_ server: Server, opensInviteBundles: Bool = true) -> GroupKeyEnvelopes {
        GroupKeyEnvelopes(
            sealer: FakeSealer(keys: keys),
            owner: owner,
            selfUserID: selfUserID,
            setEnvelope: { _, envelope in try server.set(envelope) },
            getEnvelope: { _ in try server.get() },
            resolveKey: { [creatorID, creatorKey] userID in
                guard userID == creatorID else { throw ErrorGetKeyEnvelope.notFound }
                return creatorKey
            },
            opensInviteBundles: opensInviteBundles
        )
    }

    private func inviteCopy(key: Data, wrappedBy: UserID?, wrappedByPublicKey: PublicKey? = nil) -> GroupKeyMaterial {
        .invite(
            InviteKeyBundle(
                inviteID: InviteID(data: Data(repeating: 7, count: 32)),
                keyEnvelope: InviteKeyEnvelope(scheme: 1, nonce: Data(), ciphertext: key, signature: Data()),
                secretEnvelope: InviteSecretEnvelope(scheme: 1, nonce: Data(), ciphertext: Data())
            ),
            wrappedBy: wrappedBy,
            wrappedByPublicKey: wrappedByPublicKey
        )
    }

    @Test("Storing a new key wraps it for the creator and keeps it without a fetch")
    func storeNewKey() async throws {
        let server = Server()
        let sut = envelopes(server)

        try await sut.storeNewKey(for: chat)

        #expect(server.stored?.nonce == owner.publicKey.data)
        #expect(server.stored?.ciphertext == keys.generated.first)
        #expect(try await sut.groupKey(for: chat, creator: selfUserID) == keys.generated.first)
        #expect(server.gets == 0)
    }

    @Test("An envelope already set is success, and the stored key wins over the new one")
    func alreadySetAdoptsStored() async throws {
        let first = Data(repeating: 9, count: 32)
        let server = Server(stored: ConversationKeyEnvelope(scheme: 1, nonce: Data(), ciphertext: first), wrappedBy: selfUserID)
        let sut = envelopes(server)

        try await sut.storeNewKey(for: chat)

        #expect(try await sut.groupKey(for: chat, creator: selfUserID) == first)
    }

    @Test("A failed store throws so the caller can retry only this step")
    func storeFailureThrows() async throws {
        let server = Server()
        server.setError = ErrorSetKeyEnvelope.transportFailure
        let sut = envelopes(server)

        await #expect(throws: ErrorSetKeyEnvelope.transportFailure) {
            try await sut.storeNewKey(for: chat)
        }

        server.setError = nil
        try await sut.storeNewKey(for: chat)
        #expect(server.sets == 2)
        #expect(server.stored != nil)
    }

    @Test("After a relaunch the key is opened from the self-wrapped envelope once, then cached")
    func reopensFromServer() async throws {
        let key = Data(repeating: 7, count: 32)
        let server = Server(stored: ConversationKeyEnvelope(scheme: 1, nonce: Data(), ciphertext: key), wrappedBy: selfUserID)
        let sut = envelopes(server)

        #expect(try await sut.groupKey(for: chat, creator: selfUserID) == key)
        #expect(try await sut.groupKey(for: chat, creator: selfUserID) == key)
        #expect(server.gets == 1)
    }

    @Test("An envelope someone else wrapped is not opened as the viewer's own")
    func rejectsForeignWrapper() async throws {
        let server = Server(stored: ConversationKeyEnvelope(scheme: 1, nonce: Data(), ciphertext: Data(count: 32)), wrappedBy: UUID())
        let sut = envelopes(server)

        await #expect(throws: GroupKeyNotSelfWrapped.self) {
            try await sut.groupKey(for: chat, creator: selfUserID)
        }
    }

    @Test("Wrapping for a recipient uses the stored key, generating one first when none was set")
    func wrapForRecipient() async throws {
        let server = Server()
        let sut = envelopes(server)
        let recipient = KeyPair.generate()!.publicKey

        let envelope = try await sut.wrap(for: recipient, in: chat)

        #expect(envelope.nonce == recipient.data)
        #expect(envelope.ciphertext == keys.generated.first)
        #expect(server.stored?.ciphertext == keys.generated.first)
    }

    @Test("An admitted member opens the creator's envelope with the creator's key, then stores a self-wrapped copy")
    func memberOpensCreatorWrap() async throws {
        let key = Data(repeating: 5, count: 32)
        let server = Server(stored: ConversationKeyEnvelope(scheme: 1, nonce: Data(), ciphertext: key), wrappedBy: creatorID)
        server.replaces = true
        let sut = envelopes(server)

        #expect(try await sut.groupKey(for: chat, creator: creatorID) == key)
        #expect(keys.unwrappedBy == [creatorKey])
        #expect(server.stored?.nonce == owner.publicKey.data)
        #expect(server.stored?.ciphertext == key)
    }

    @Test("A failed self-wrap still returns the key the creator's envelope opened")
    func memberSelfWrapFailureIsBestEffort() async throws {
        let key = Data(repeating: 5, count: 32)
        let server = Server(stored: ConversationKeyEnvelope(scheme: 1, nonce: Data(), ciphertext: key), wrappedBy: creatorID)
        server.setError = ErrorSetKeyEnvelope.transportFailure
        let sut = envelopes(server)

        #expect(try await sut.groupKey(for: chat, creator: creatorID) == key)
        #expect(server.sets == 1)
    }

    @Test("A member with no envelope yet doesn't generate a key; only the creator does")
    func memberNoEnvelopeThrows() async throws {
        let server = Server()
        let sut = envelopes(server)

        await #expect(throws: ErrorGetKeyEnvelope.noEnvelope) {
            try await sut.groupKey(for: chat, creator: creatorID)
        }
        #expect(server.sets == 0)
        #expect(keys.generated.isEmpty)
    }

    // MARK: - Invite copy -

    @Test("An invite-joined member opens the invite's copy with the creator's key, then stores their own")
    func inviteCopyOpensAndSelfWraps() async throws {
        let key = Data(repeating: 4, count: 32)
        let server = Server()
        server.inviteCopy = inviteCopy(key: key, wrappedBy: creatorID)
        let sut = envelopes(server)

        #expect(try await sut.groupKey(for: chat, creator: creatorID) == key)
        #expect(keys.bundleOpens.map(\.creatorPublicKey) == [creatorKey])
        #expect(keys.bundleOpens.map(\.wrappedByCreator) == [true])
        #expect(server.sets == 1)
        #expect(server.stored?.nonce == owner.publicKey.data)
        #expect(server.stored?.ciphertext == key)

        // Cached: no second fetch, and a fresh instance opens the stored self-wrap, not the bundle.
        #expect(try await sut.groupKey(for: chat, creator: creatorID) == key)
        #expect(server.gets == 1)
        #expect(try await envelopes(server).groupKey(for: chat, creator: creatorID) == key)
        #expect(keys.bundleOpens.count == 1)
    }

    @Test("A bundle that fails a check is the wrong-key state, and nothing is stored")
    func inviteCopyRejected() async throws {
        let server = Server()
        server.inviteCopy = inviteCopy(key: Data(repeating: 4, count: 32), wrappedBy: creatorID)
        keys.bundleError = GroupKeyUnusable(failsAt: .signature)
        let sut = envelopes(server)

        await #expect(throws: GroupKeyUnusable(failsAt: .signature)) {
            try await sut.groupKey(for: chat, creator: creatorID)
        }
        #expect(server.sets == 0)
    }

    @Test("A bundle someone other than the creator wrapped is rejected, never re-keyed")
    func inviteCopyWrongWrapper() async throws {
        let server = Server()
        server.inviteCopy = inviteCopy(key: Data(repeating: 4, count: 32), wrappedBy: UUID(), wrappedByPublicKey: KeyPair.generate()!.publicKey)
        let sut = envelopes(server)

        await #expect(throws: GroupKeyUnusable(failsAt: .wrappedBy)) {
            try await sut.groupKey(for: chat, creator: creatorID)
        }
        #expect(keys.bundleOpens.map(\.wrappedByCreator) == [false])
        #expect(keys.generated.isEmpty)
        #expect(server.sets == 0)
    }

    @Test("A failed self-wrap still returns the key, and the next launch opens the invite's copy again")
    func inviteCopySelfWrapFailsThenRetries() async throws {
        let key = Data(repeating: 4, count: 32)
        let server = Server()
        server.inviteCopy = inviteCopy(key: key, wrappedBy: creatorID)
        server.setError = ErrorSetKeyEnvelope.unknown

        #expect(try await envelopes(server).groupKey(for: chat, creator: creatorID) == key)
        #expect(server.stored == nil)

        server.setError = nil
        #expect(try await envelopes(server).groupKey(for: chat, creator: creatorID) == key)
        #expect(keys.bundleOpens.count == 2)
        #expect(server.stored?.ciphertext == key)
    }

    @Test("A failed fetch caches nothing, so the next call fetches and opens the invite's copy")
    func inviteCopyFetchFailsThenRetries() async throws {
        let key = Data(repeating: 4, count: 32)
        let server = Server()
        server.inviteCopy = inviteCopy(key: key, wrappedBy: creatorID)
        server.getError = ErrorGetKeyEnvelope.transportFailure
        let sut = envelopes(server)

        await #expect(throws: ErrorGetKeyEnvelope.self) {
            try await sut.groupKey(for: chat, creator: creatorID)
        }

        server.getError = nil
        #expect(try await sut.groupKey(for: chat, creator: creatorID) == key)
    }

    @Test("The creator's key falls back to the one sent with the bundle when it can't be resolved")
    func inviteCopyFallsBackToSentKey() async throws {
        let key = Data(repeating: 4, count: 32)
        let unresolved = UUID()
        let sentKey = KeyPair.generate()!.publicKey
        let server = Server()
        server.inviteCopy = inviteCopy(key: key, wrappedBy: unresolved, wrappedByPublicKey: sentKey)

        #expect(try await envelopes(server).groupKey(for: chat, creator: unresolved) == key)
        #expect(keys.bundleOpens.map(\.creatorPublicKey) == [sentKey])
    }

    @Test("An instance that doesn't open invite copies leaves them unopened and writes nothing")
    func inviteCopyNotOpenedByExtension() async throws {
        let server = Server()
        server.inviteCopy = inviteCopy(key: Data(repeating: 4, count: 32), wrappedBy: creatorID)
        let sut = envelopes(server, opensInviteBundles: false)

        await #expect(throws: InviteBundleNotOpened.self) {
            try await sut.groupKey(for: chat, creator: creatorID)
        }
        #expect(keys.bundleOpens.isEmpty)
        #expect(server.sets == 0)
    }

    @Test("An invite copy whose creator isn't known yet is retried later, not marked wrong-key")
    func inviteCopyCreatorUnknown() async throws {
        let server = Server()
        server.inviteCopy = inviteCopy(key: Data(repeating: 4, count: 32), wrappedBy: creatorID)

        await #expect(throws: InviteBundleNotOpened.self) {
            try await envelopes(server).groupKey(for: chat, creator: nil)
        }
        #expect(keys.bundleOpens.isEmpty)
    }
}
