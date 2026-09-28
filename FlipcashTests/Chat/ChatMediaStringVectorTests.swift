//
//  ChatMediaStringVectorTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
import FlipcashCore
import FlipcashStore
@testable import Flipcash

@Suite("Chat media string vectors")
@MainActor
struct ChatMediaStringVectorTests {

    private final class BundleToken {}

    struct Vector: Decodable {
        struct Expected: Decodable {
            let snippet: String
            let preview: String
        }
        let name: String
        let caption: String?
        let expected: Expected
    }

    private struct Fixture: Decodable {
        let strings: [Vector]
    }

    private static func vectors() throws -> [Vector] {
        let url = try #require(Bundle(for: BundleToken.self).url(forResource: "chat_media", withExtension: "json"))
        let vectors = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url)).strings
        #expect(!vectors.isEmpty)
        return vectors
    }

    private func photoMessage(caption: String?) -> ConversationMessage {
        ConversationMessage(
            id: MessageID(value: 1),
            senderID: nil,
            content: .media([MediaAttachment(blobID: BlobID(data: Data([1])), width: 100, height: 100, blurhash: nil)], caption: caption),
            date: Date(timeIntervalSince1970: 1),
            unreadSeq: 1
        )
    }

    private func conversation(lastMessage: ConversationMessage) -> Conversation {
        Conversation(
            id: ConversationID.test(1),
            members: [],
            lastMessage: lastMessage,
            lastActivity: Date(timeIntervalSince1970: 1)
        )
    }

    @Test("The quote snippet and list preview match every strings vector")
    func helperMatchesFixture() throws {
        for vector in try Self.vectors() {
            #expect(ChatMediaStrings.quoteSnippet(caption: vector.caption) == vector.expected.snippet, "\(vector.name)")
            #expect(ChatMediaStrings.listPreview(caption: vector.caption) == vector.expected.preview, "\(vector.name)")
        }
    }

    @Test("The conversation list previews a photo with the fixture's preview")
    func conversationListMatchesFixture() throws {
        let mock = MockConversations()
        let controller = ConversationController(
            fetching: mock, membership: mock, viewerSettings: mock, messaging: mock, streaming: mock,
            contactNaming: MockDMContactNaming(),
            database: try Database.makeTemp().database,
            owner: .generate()!, selfUserID: UUID(),
            typingHeartbeatInterval: .seconds(3), incomingTypingExpiry: .seconds(10)
        )

        for vector in try Self.vectors() {
            let preview = controller.lastMessagePreview(for: conversation(lastMessage: photoMessage(caption: vector.caption))) { _ -> String? in nil }
            #expect(preview == vector.expected.preview, "\(vector.name)")
        }
    }

    @Test("Spotlight describes a photo with the fixture's preview")
    func spotlightMatchesFixture() throws {
        for vector in try Self.vectors() {
            let item = ChatSpotlightItem(
                conversation: conversation(lastMessage: photoMessage(caption: vector.caption)),
                displayName: "Anna",
                counterpartPhoneE164: nil,
                thumbnailData: nil
            )
            #expect(item.contentDescription == vector.expected.preview, "\(vector.name)")
        }
    }

    @Test("A reply to a photo quotes it with the fixture's snippet")
    func quoteMatchesFixture() throws {
        for vector in try Self.vectors() {
            let original = photoMessage(caption: vector.caption)
            let reply = ConversationMessage(
                id: MessageID(value: 2),
                senderID: nil,
                content: .text("nice"),
                date: Date(timeIntervalSince1970: 2),
                unreadSeq: 2,
                repliedTo: original.id
            )
            let quotes = ChatItem.from(
                [original, reply],
                selfUserID: UUID(),
                cashBranding: { _ in ("Cash", nil) },
                counterpartName: "Ada",
                quotedMessage: { $0 == original.id ? original : nil }
            ).compactMap { item in
                if case .message(let message) = item { return message.quote } else { return nil }
            }
            let quote = try #require(quotes.first)
            #expect(quote.snippet == vector.expected.snippet, "\(vector.name)")
        }
    }
}
