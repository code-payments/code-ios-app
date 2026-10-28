//
//  SharedCoreGroupKeySealerTests.swift
//  FlipcashCoreTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Testing
@testable import FlipcashCore

@Suite("Shared-core group key sealer")
struct SharedCoreGroupKeySealerTests {

    private let sealer = SharedCoreGroupKeySealer()
    private let host = KeyPair.generate()!
    private let member = KeyPair.generate()!
    private let chat = ConversationID(data: Data(repeating: 7, count: 32))

    @Test("A key wrapped for a member opens with the member's key and the host as wrapper")
    func roundTripsToMember() throws {
        let key = sealer.newGroupKey()
        let envelope = try sealer.wrap(groupKey: key, owner: host, recipient: member.publicKey, conversationID: chat)

        #expect(key.count == 32)
        #expect(envelope.nonce.count == 24)
        #expect(envelope.ciphertext.count == 48)
        #expect(try sealer.unwrap(envelope, owner: member, wrapper: host.publicKey, conversationID: chat) == key)
    }

    @Test("A self-wrapped key opens with the host as both sides")
    func roundTripsToSelf() throws {
        let key = sealer.newGroupKey()
        let envelope = try sealer.wrap(groupKey: key, owner: host, recipient: host.publicKey, conversationID: chat)

        #expect(try sealer.unwrap(envelope, owner: host, wrapper: host.publicKey, conversationID: chat) == key)
    }

    @Test("An envelope bound to one chat does not open in another")
    func rejectsOtherChat() throws {
        let envelope = try sealer.wrap(groupKey: sealer.newGroupKey(), owner: host, recipient: member.publicKey, conversationID: chat)
        let other = ConversationID(data: Data(repeating: 8, count: 32))

        #expect(throws: (any Error).self) {
            try sealer.unwrap(envelope, owner: member, wrapper: host.publicKey, conversationID: other)
        }
    }

    @Test("A bundle in a scheme this build doesn't know is unsupported, not the wrong key")
    func inviteBundleUnknownScheme() {
        let bundle = InviteKeyBundle(
            inviteID: InviteID(data: Data(repeating: 1, count: 32)),
            keyEnvelope: InviteKeyEnvelope(scheme: 99, nonce: Data(count: 24), ciphertext: Data(count: 48), signature: Data(count: 64)),
            secretEnvelope: InviteSecretEnvelope(scheme: 1, nonce: Data(count: 24), ciphertext: Data(count: 48))
        )

        #expect(throws: UnsupportedKeyEnvelopeScheme.self) {
            try sealer.open(bundle, owner: member, creatorPublicKey: host.publicKey, wrappedByCreator: true, conversationID: chat)
        }
    }
}
