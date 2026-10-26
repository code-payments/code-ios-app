//
//  PaymentRequestTextVectorTests.swift
//  FlipcashCoreVectorsTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
import SharedCore
@testable import FlipcashCore

/// Reproduces `payment_request_text.json` (canonical copy in the orchestrator's `test-vectors/`)
/// through `ChatSeal`, which reaches shared-core's request-text cipher. The nonce'd encrypt overload
/// is not exported to Swift, so encryption is checked byte for byte on the Kotlin side and by
/// round trip here; decryption is checked byte for byte.
@Suite("Payment request text vectors")
struct PaymentRequestTextVectorTests {

    private struct Vectors: Decodable {
        struct Text: Decodable {
            let name: String
            let title: String
            let description: String
            let nonce: String
            let ciphertext: String
        }
        struct Reject: Decodable {
            let name: String
            let chatKey: String
            let nonce: String
            let ciphertext: String
            let aad: String
        }
        let label: String
        let chatKey: String
        let chatId: String
        let creatorId: String
        let texts: [Text]
        let rejects: [Reject]
    }

    private let vectors: Vectors

    init() throws {
        let url = try #require(Bundle.module.url(forResource: "payment_request_text", withExtension: "json", subdirectory: "Fixtures"))
        vectors = try JSONDecoder().decode(Vectors.self, from: Data(contentsOf: url))
    }

    private func seal(key: String, chat: Data, selfID: UUID) throws -> ChatSeal {
        ChatSeal(
            cipher: DefaultChatCipher.shared,
            groupKey: try hex(key),
            conversationID: ConversationID(data: chat),
            selfUserID: selfID
        )
    }

    @Test("Every text case decrypts to its title and description")
    func textsDecrypt() throws {
        #expect(vectors.texts.count == 4)
        let creator = try UUID(data: hex(vectors.creatorId))
        let seal = try seal(key: vectors.chatKey, chat: hex(vectors.chatId), selfID: UUID())
        for v in vectors.texts {
            let opened = try seal.openRequestText(
                scheme: ChatSeal.requestTextScheme.rawValue,
                nonce: hex(v.nonce),
                ciphertext: hex(v.ciphertext),
                creator: creator
            )
            #expect(opened.title == v.title, "\(v.name)")
            #expect(opened.description == v.description, "\(v.name)")
        }
    }

    @Test("Every text case round-trips through a fresh nonce")
    func textsRoundTrip() throws {
        let creator = try UUID(data: hex(vectors.creatorId))
        let seal = try seal(key: vectors.chatKey, chat: hex(vectors.chatId), selfID: creator)
        for v in vectors.texts {
            let sealed = try seal.sealRequestText(title: v.title, description: v.description)
            guard case .encrypted(let scheme, let nonce, let ciphertext) = sealed else {
                Issue.record("\(v.name): sealed as plaintext")
                continue
            }
            #expect(nonce.count == 24, "\(v.name)")
            #expect(nonce != (try hex(v.nonce)), "\(v.name)")
            #expect(ciphertext.count == (try hex(v.ciphertext)).count, "\(v.name)")
            let opened = try seal.openRequestText(scheme: scheme, nonce: nonce, ciphertext: ciphertext, creator: creator)
            #expect(opened.title == v.title, "\(v.name)")
            #expect(opened.description == v.description, "\(v.name)")
        }
    }

    @Test("Every reject case fails to decrypt")
    func rejectsFail() throws {
        #expect(vectors.rejects.count == 5)
        let label = Data(vectors.label.utf8)
        for v in vectors.rejects {
            let aad = try hex(v.aad)
            // The cipher always builds the aad from the request label, so a case that names another
            // label is unreachable from Swift; its raw-aad check runs in the Kotlin vector test.
            guard aad.prefix(label.count) == label else {
                #expect(aad != label + (try hex(vectors.chatId)) + (try hex(vectors.creatorId)), "\(v.name)")
                continue
            }
            let chat = aad.subdata(in: label.count..<label.count + 32)
            let creator = aad.subdata(in: label.count + 32..<aad.count)
            let seal = try seal(key: v.chatKey, chat: chat, selfID: UUID())
            #expect(throws: (any Error).self, "\(v.name)") {
                try seal.openRequestText(
                    scheme: ChatSeal.requestTextScheme.rawValue,
                    nonce: hex(v.nonce),
                    ciphertext: hex(v.ciphertext),
                    creator: UUID(data: creator)
                )
            }
        }
    }

    @Test("An unknown scheme is unsupported")
    func unknownScheme() throws {
        let v = try #require(vectors.texts.first)
        let seal = try seal(key: vectors.chatKey, chat: hex(vectors.chatId), selfID: UUID())
        #expect(throws: RequestTextFailure.unsupported) {
            try seal.openRequestText(scheme: 99, nonce: hex(v.nonce), ciphertext: hex(v.ciphertext), creator: UUID(data: hex(vectors.creatorId)))
        }
    }

    private func hex(_ string: String) throws -> Data {
        var data = Data(capacity: string.count / 2)
        var index = string.startIndex
        while index < string.endIndex {
            let next = string.index(index, offsetBy: 2)
            data.append(try #require(UInt8(string[index..<next], radix: 16)))
            index = next
        }
        return data
    }
}
