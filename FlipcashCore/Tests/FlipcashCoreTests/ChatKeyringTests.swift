//
//  ChatKeyringTests.swift
//  FlipcashCoreTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
import FlipcashAPI
import SharedCore
@testable import FlipcashCore

/// SharedCore exports its own `KeyPair`; these tests mean the app's.
private typealias KeyPair = FlipcashCore.KeyPair

@Suite("ChatKeyring")
struct ChatKeyringTests {

    private final class MemoryKeyStore: PeerKeyStore, @unchecked Sendable {
        private let lock = NSLock()
        private var keys: [UserID: PublicKey] = [:]
        func key(for userID: UserID) -> PublicKey? { lock.withLock { keys[userID] } }
        func store(_ key: PublicKey, for userID: UserID) { lock.withLock { keys[userID] = key } }
    }

    private final class Resolver: @unchecked Sendable {
        private let lock = NSLock()
        private var _calls = 0
        var calls: Int { lock.withLock { _calls } }
        let result: Result<PublicKey, Error>
        init(_ result: Result<PublicKey, Error>) { self.result = result }
        func resolve(_: UserID) throws -> PublicKey {
            lock.withLock { _calls += 1 }
            return try result.get()
        }
    }

    private struct Offline: Error {}

    private let alice = KeyPair.generate()!
    private let bob = KeyPair.generate()!
    private let aliceID = UUID()
    private let bobID = UUID()

    private func dm(type: ConversationType = .contactDm, useE2Ee: Bool = true, members: [UUID]? = nil) -> Conversation {
        Conversation(
            id: ConversationID(data: Data(repeating: 3, count: 32)),
            members: (members ?? [aliceID, bobID]).map { ConversationMember(userID: $0, displayName: "m") },
            lastMessage: nil,
            lastActivity: Date(timeIntervalSince1970: 0),
            type: type,
            useE2Ee: useE2Ee
        )
    }

    private func keyring(_ resolver: Resolver, store: PeerKeyStore = MemoryKeyStore(), owner: KeyPair? = nil, selfID: UUID? = nil) -> ChatKeyring {
        ChatKeyring(cipher: DefaultChatCipher.shared, owner: owner ?? alice, selfUserID: selfID ?? aliceID, store: store) { try resolver.resolve($0) }
    }

    /// An encrypted message from Bob to Alice in `dm()`.
    private func fromBob(_ text: String) async throws -> ConversationMessage {
        let bobRing = keyring(Resolver(.success(alice.publicKey)), owner: bob, selfID: bobID)
        let seal = try #require(try await bobRing.sealForSending(in: dm()))
        let proto = Flipcash_Messaging_V1_Message.with {
            $0.messageID = MessageID(value: 1).proto
            $0.senderID = bobID.proto
            $0.content = [try! seal.seal(text: text, repliedTo: nil)]
        }
        return try #require(ConversationMessage(proto))
    }

    @Test("A chat the policy exempts is sent in plaintext without fetching a key")
    func plaintextChat() async throws {
        let resolver = Resolver(.success(bob.publicKey))
        let ring = keyring(resolver)

        #expect(try await ring.sealForSending(in: dm(useE2Ee: false)) == nil)
        #expect(try await ring.sealForSending(in: dm(type: .group)) == nil)
        #expect(resolver.calls == 0)
    }

    @Test("An encrypting DM seals with the peer's resolved key, fetched once and stored")
    func encryptingDM() async throws {
        let resolver = Resolver(.success(bob.publicKey))
        let store = MemoryKeyStore()
        let ring = keyring(resolver, store: store)

        #expect(try await ring.sealForSending(in: dm()) != nil)
        #expect(try await ring.sealForSending(in: dm()) != nil)
        #expect(resolver.calls == 1)
        #expect(store.key(for: bobID) == bob.publicKey)
    }

    @Test("A stored key is used without resolving")
    func storedKey() async throws {
        let resolver = Resolver(.failure(Offline()))
        let store = MemoryKeyStore()
        store.store(bob.publicKey, for: bobID)

        #expect(try await keyring(resolver, store: store).sealForSending(in: dm()) != nil)
        #expect(resolver.calls == 0)
    }

    @Test("Sending fails rather than going out in plaintext when the key can't be fetched")
    func sendOffline() async {
        let ring = keyring(Resolver(.failure(Offline())))

        await #expect(throws: PeerKeyUnavailable.self) { try await ring.sealForSending(in: dm()) }
    }

    @Test("Received messages decrypt with the peer's key")
    func receive() async throws {
        let ring = keyring(Resolver(.success(bob.publicKey)))
        let opened = await ring.open(try await fromBob("hello"), in: dm())

        #expect(opened.content == .text("hello"))
    }

    @Test("A key-fetch failure leaves messages waiting, not failed, and a later open decrypts them")
    func receiveOffline() async throws {
        let message = try await fromBob("hello")
        let store = MemoryKeyStore()

        let waiting = await keyring(Resolver(.failure(Offline())), store: store).open(message, in: dm())
        #expect(waiting.isAwaitingDecryption)
        #expect(waiting.decryptFailure == nil)

        let opened = await keyring(Resolver(.success(bob.publicKey)), store: store).open(waiting, in: dm())
        #expect(opened.content == .text("hello"))
    }

    @Test("Encrypted content in a group can't be decrypted and is unsupported")
    func group() async throws {
        let opened = await keyring(Resolver(.success(bob.publicKey))).open(try await fromBob("hello"), in: dm(type: .group))

        #expect(opened.decryptFailure == .unsupported)
    }

    @Test("Plaintext messages pass through untouched")
    func plaintext() async {
        let resolver = Resolver(.failure(Offline()))
        let message = ConversationMessage(id: MessageID(value: 1), senderID: bobID, content: .text("hi"), date: .now, unreadSeq: 1)

        #expect(await keyring(resolver).open(message, in: dm()) == message)
        #expect(resolver.calls == 0)
    }
}
