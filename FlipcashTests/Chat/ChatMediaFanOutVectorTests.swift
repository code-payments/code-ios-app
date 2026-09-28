//
//  ChatMediaFanOutVectorTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("Chat media fan-out vectors")
struct ChatMediaFanOutVectorTests {

    private final class BundleToken {}

    struct ExpectedMessage: Decodable {
        let kind: String
        let chip: String?
        let caption: String?
        let text: String?
        let replyTo: String?
    }

    struct Vector: Decodable {
        let name: String
        let chips: [String]
        let text: String?
        let replyTo: String?
        let messages: [ExpectedMessage]
    }

    private struct Fixture: Decodable {
        let fanOut: [Vector]
    }

    /// The fixture's message names mapped onto ids; only the identity matters.
    static let replyIDs: [String: MessageID] = ["m1": MessageID(value: 7)]

    static func loadVectors() throws -> [Vector] {
        let url = try #require(Bundle(for: BundleToken.self).url(forResource: "chat_media", withExtension: "json"))
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url)).fanOut
    }

    @Test("The send plan matches every fanOut vector")
    func matchesFixture() throws {
        let vectors = try Self.loadVectors()
        #expect(!vectors.isEmpty)

        for vector in vectors {
            let plan = ChatMediaSendPlan.messages(
                chips: vector.chips,
                text: vector.text,
                replyTo: vector.replyTo.flatMap { Self.replyIDs[$0] }
            )
            #expect(plan.count == vector.messages.count, "\(vector.name)")

            for (built, expected) in zip(plan, vector.messages) {
                let expectedReply = expected.replyTo.flatMap { Self.replyIDs[$0] }
                switch built {
                case .text(let text, let replyTo):
                    #expect(expected.kind == "text", "\(vector.name)")
                    #expect(text == expected.text, "\(vector.name)")
                    #expect(replyTo == expectedReply, "\(vector.name)")
                case .media(let message):
                    #expect(expected.kind == "media", "\(vector.name)")
                    #expect(message.chip == expected.chip, "\(vector.name)")
                    #expect(message.caption == expected.caption, "\(vector.name)")
                    #expect(message.replyTo == expectedReply, "\(vector.name)")
                }
            }
        }
    }
}
