//
//  ChatMediaStackMappingTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
import FlipcashCore
import FlipcashUI
@testable import Flipcash

/// `chat_media_groups.json` run through the transcript mapper: each stack draws as one row fronted
/// by its first photo, carrying every member. The canonical copy lives in the orchestrator repo;
/// this one is synced byte for byte and never edited here.
@MainActor
@Suite("Photo stacks in the transcript")
struct ChatMediaStackMappingTests {

    struct Message: Decodable, Sendable {
        let seq: UInt64
        let sender: String
        let kind: String
        let ts: Double
        let hasCaption: Bool
        let isReply: Bool
    }

    struct Vector: Decodable, Sendable, CustomTestStringConvertible {
        let name: String
        let note: String
        let messages: [Message]
        let stacks: [[UInt64]]

        var testDescription: String { name }
    }

    struct Fixture: Decodable {
        let cases: [Vector]
    }

    nonisolated private final class BundleToken {}

    nonisolated static let vectors: [Vector] = (try? loadFixture().cases) ?? []

    nonisolated private static func loadFixture() throws -> Fixture {
        let url = try #require(Bundle(for: BundleToken.self).url(forResource: "chat_media_groups", withExtension: "json"))
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    private let me = UUID()
    private let base = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_000_000))
        .addingTimeInterval(9 * 60 * 60)

    @Test func fixtureLoadsAllCases() throws {
        #expect(try Self.loadFixture().cases.count == 12)
    }

    @Test(arguments: vectors)
    func stacksMatchTheCrossPlatformVector(_ vector: Vector) {
        var senders: [String: UUID] = [:]
        let messages = vector.messages.map { message in
            let sender = senders[message.sender] ?? UUID()
            senders[message.sender] = sender
            let attachment = MediaAttachment(blobID: BlobID(data: Data([UInt8(message.seq)])), width: 300, height: 400, blurhash: nil)
            let content: ConversationMessage.Content = message.kind == "photo"
                ? .media([attachment], caption: message.hasCaption ? "caption \(message.seq)" : nil)
                : .text("text \(message.seq)")
            return ConversationMessage(
                id: MessageID(value: message.seq),
                senderID: sender,
                content: content,
                date: base.addingTimeInterval(message.ts),
                unreadSeq: message.seq,
                repliedTo: message.isReply ? MessageID(value: 1_000) : nil
            )
        }
        let ids = Dictionary(uniqueKeysWithValues: messages.map { ($0.stableID, $0.id.value) })

        let stacks = ChatItem.from(messages, selfUserID: me).compactMap { item -> [UInt64]? in
            guard case .message(let row) = item, case .media(let media) = row.content, !media.stackPhotos.isEmpty else { return nil }
            return media.stackPhotos.compactMap { ids[$0.messageID] }
        }

        #expect(stacks == vector.stacks, "\(vector.note)")
    }

    @Test("Only a stack's front offers Save All; a photo drawn alone offers Save Photo only")
    func saveAllIsOnTheStackFront() {
        let them = UUID()
        func photo(_ seq: UInt64, after offset: TimeInterval) -> ConversationMessage {
            ConversationMessage(
                id: MessageID(value: seq),
                senderID: them,
                content: .media([MediaAttachment(blobID: BlobID(data: Data([UInt8(seq)])), width: 300, height: 400, blurhash: nil)], caption: nil),
                date: base.addingTimeInterval(offset),
                unreadSeq: seq
            )
        }
        let messages = [photo(1, after: 0), photo(2, after: 0.5), photo(3, after: 60)]

        let actions = ChatItem.from(messages, selfUserID: me, capabilities: { _ in [.reply, .savePhoto] }).compactMap { item -> [MessageCapability]? in
            guard case .message(let row) = item, case .media = row.content else { return nil }
            return row.actions
        }

        #expect(actions.count == 2)
        #expect(actions.first?.contains(.saveAllPhotos) == true)
        #expect(actions.last?.contains(.saveAllPhotos) == false)
        #expect(actions.last?.contains(.savePhoto) == true)
    }
}
