//
//  PaymentRequestsSealTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Testing
import SharedCore
@testable import FlipcashCore
@testable import Flipcash

/// An encrypted request title waits on the chat's seal, so a failed seal read must not strand it.
@MainActor
@Suite("Payment requests: chat seal retries")
struct PaymentRequestsSealTests {

    private let chat = ConversationID.test(1)

    private static func seal() throws -> ChatSeal {
        try ChatSeal(
            cipher: DefaultChatCipher.shared,
            owner: KeyPair.generate()!,
            peerPublicKey: KeyPair.generate()!.publicKey,
            conversationID: ConversationID(data: Data(repeating: 0x07, count: 32)),
            selfUserID: UUID()
        )
    }

    /// Answers `nil` until `available` is set, counting reads.
    @MainActor
    private final class SealSource {
        var available: ChatSeal?
        var reads = 0
    }

    private func store(_ source: SealSource) -> PaymentRequests {
        PaymentRequests(
            getChatPage: { _, _, _ in [] },
            getRequest: { _ in throw ErrorGetPaymentRequest.unknown },
            openingSeal: { _ in
                source.reads += 1
                return source.available
            }
        )
    }

    @Test("A chat refresh retries a seal the last read could not open")
    func refreshChatRetriesSeal() async throws {
        let source = SealSource()
        let store = store(source)

        await store.refreshChat(chat)
        #expect(store.seal(for: chat) == nil)

        source.available = try Self.seal()
        await store.refreshChat(chat)
        #expect(store.seal(for: chat) != nil)
    }

    @Test("A held seal is not read again")
    func heldSealIsKept() async throws {
        let source = SealSource()
        source.available = try Self.seal()
        let store = store(source)

        await store.refreshChat(chat)
        await store.refreshChat(chat)
        #expect(source.reads == 1)
    }
}
