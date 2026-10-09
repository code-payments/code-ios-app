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
            var generated: [Data] { lock.withLock { _generated } }
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
            envelope.ciphertext
        }
    }

    private final class Server: @unchecked Sendable {
        private let lock = NSLock()
        private var _stored: ConversationKeyEnvelope?
        private var _sets = 0
        private var _gets = 0
        var wrappedBy: UserID?
        var setError: Error?

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
                if _stored != nil { throw ErrorSetKeyEnvelope.alreadySet }
                _stored = envelope
            }
        }

        func get() throws -> (envelope: ConversationKeyEnvelope, wrappedBy: UserID?) {
            try lock.withLock {
                _gets += 1
                guard let _stored else { throw ErrorGetKeyEnvelope.noEnvelope }
                return (_stored, wrappedBy)
            }
        }
    }

    private let owner = KeyPair.generate()!
    private let selfUserID = UUID()
    private let chat = ConversationID(data: Data(repeating: 3, count: 32))
    private let keys = FakeSealer.Keys()

    private func envelopes(_ server: Server) -> GroupKeyEnvelopes {
        GroupKeyEnvelopes(
            sealer: FakeSealer(keys: keys),
            owner: owner,
            selfUserID: selfUserID,
            setEnvelope: { _, envelope in try server.set(envelope) },
            getEnvelope: { _ in try server.get() }
        )
    }

    @Test("Storing a new key wraps it for the creator and keeps it without a fetch")
    func storeNewKey() async throws {
        let server = Server()
        let sut = envelopes(server)

        try await sut.storeNewKey(for: chat)

        #expect(server.stored?.nonce == owner.publicKey.data)
        #expect(server.stored?.ciphertext == keys.generated.first)
        #expect(try await sut.groupKey(for: chat) == keys.generated.first)
        #expect(server.gets == 0)
    }

    @Test("An envelope already set is success, and the stored key wins over the new one")
    func alreadySetAdoptsStored() async throws {
        let first = Data(repeating: 9, count: 32)
        let server = Server(stored: ConversationKeyEnvelope(scheme: 1, nonce: Data(), ciphertext: first), wrappedBy: selfUserID)
        let sut = envelopes(server)

        try await sut.storeNewKey(for: chat)

        #expect(try await sut.groupKey(for: chat) == first)
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

        #expect(try await sut.groupKey(for: chat) == key)
        #expect(try await sut.groupKey(for: chat) == key)
        #expect(server.gets == 1)
    }

    @Test("An envelope someone else wrapped is not opened as the viewer's own")
    func rejectsForeignWrapper() async throws {
        let server = Server(stored: ConversationKeyEnvelope(scheme: 1, nonce: Data(), ciphertext: Data(count: 32)), wrappedBy: UUID())
        let sut = envelopes(server)

        await #expect(throws: GroupKeyNotSelfWrapped.self) {
            try await sut.groupKey(for: chat)
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
}
