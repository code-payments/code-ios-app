//
//  Regression_6ace7ba489c0031619d1c6c8.swift
//  Flipcash
//
//  Share send failed: NoPeer. The share extension built its ChatKeyring without a group-key
//  source, so every share into a private group threw NoPeer from ChatKeyring.groupSeal.
//
//  Fix: ChatKeyring requires a group-key source, and the share extension builds its keyring
//  from the chat's key envelopes, as the notification extension does.
//

import Foundation
import Testing
@testable import FlipcashCore

@Suite("Regression: 6ace7ba – Share to a private group throws NoPeer", .bug("6ace7ba489c0031619d1c6c8"))
struct Regression_6ace7ba {

    private let owner = KeyPair.generate()!
    private let selfUserID = UUID()
    private let chatID = ConversationID(data: Data(repeating: 7, count: 32))

    private func privateGroup() -> Conversation {
        var group = Conversation(
            id: chatID,
            members: [selfUserID, UUID()].map { ConversationMember(userID: $0, displayName: "m") },
            lastMessage: nil,
            lastActivity: Date(timeIntervalSince1970: 0),
            type: .group,
            useE2Ee: true
        )
        group.isPrivate = true
        return group
    }

    @Test("A keyring built from key envelopes seals a private group")
    func privateGroupSeals() async throws {
        let sealer = SharedCoreGroupKeySealer()
        let envelope = try sealer.wrap(groupKey: sealer.newGroupKey(), owner: owner, recipient: owner.publicKey, conversationID: chatID)
        let keyring = ChatKeyring(
            owner: owner,
            selfUserID: selfUserID,
            resolveKey: { _ in throw ErrorGetKeyEnvelope.notFound },
            setEnvelope: { _, _ in },
            getEnvelope: { _ in .own(envelope: envelope, wrappedBy: nil) },
            opensInviteBundles: false
        )

        let seal = try #require(try await keyring.sealForSending(in: privateGroup()))

        #expect(try seal.seal(text: "hi", repliedTo: nil).encrypted.scheme == .chatKeyXchacha20Poly1305)
    }
}
