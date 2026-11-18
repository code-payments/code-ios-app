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

    // MARK: - A send still in flight

    private func myPhoto(_ seq: UInt64?, after offset: TimeInterval, status: SendStatus = .sent, caption: String? = nil) -> ConversationMessage {
        ConversationMessage(
            id: seq.map { MessageID(value: $0) } ?? .unassigned,
            senderID: me,
            content: .media([MediaAttachment(blobID: seq.map { BlobID(data: Data([UInt8($0)])) }, width: 300, height: 400, blurhash: nil)], caption: caption),
            date: base.addingTimeInterval(offset),
            unreadSeq: seq ?? 0,
            status: status,
            clientMessageID: seq == nil ? UUID() : nil
        )
    }

    /// Each stack in the mapped transcript, as its members' stable ids.
    private func stackIDs(_ messages: [ConversationMessage]) -> [[String]] {
        ChatItem.from(messages, selfUserID: me).compactMap { item -> [String]? in
            guard case .message(let row) = item, case .media(let media) = row.content, !media.stackPhotos.isEmpty else { return nil }
            return media.stackPhotos.map(\.messageID)
        }
    }

    @Test("A send's photos stack while they upload, before any has a server id")
    func pendingSendStacks() {
        let messages = [myPhoto(nil, after: 0, status: .sending), myPhoto(nil, after: 0.01, status: .sending), myPhoto(nil, after: 0.02, status: .sending, caption: "sunrise")]
        #expect(stackIDs(messages) == [messages.map(\.stableID)])
    }

    @Test("A send part way through posting stays one stack")
    func halfPostedSendStacks() {
        let messages = [myPhoto(1, after: 0), myPhoto(2, after: 0.5), myPhoto(nil, after: 0.6, status: .sending)]
        #expect(stackIDs(messages) == [messages.map(\.stableID)])
    }

    @Test("A stack's confirmed photos carry their server ids, so the READ pointer can reach the newest")
    func stackPhotosCarryServerIDs() {
        let messages = [myPhoto(1, after: 0), myPhoto(2, after: 0.5), myPhoto(nil, after: 0.6, status: .sending)]
        let serverIDs = ChatItem.from(messages, selfUserID: me).compactMap { item -> [MessageID?]? in
            guard case .message(let row) = item, case .media(let media) = row.content, !media.stackPhotos.isEmpty else { return nil }
            return media.stackPhotos.map(\.serverID)
        }
        #expect(serverIDs == [[MessageID(value: 1), MessageID(value: 2), nil]])
    }

    @Test("A photo that failed to send leaves the stack and keeps its own bubble")
    func failedPhotoLeavesTheStack() {
        let messages = [myPhoto(nil, after: 0, status: .sending), myPhoto(nil, after: 0.01, status: .sending), myPhoto(nil, after: 0.02, status: .failed)]
        #expect(stackIDs(messages) == [[messages[0].stableID, messages[1].stableID]])
    }

    @Test("A pending photo doesn't join a photo sent minutes before it")
    func pendingPhotoKeepsTheWindow() {
        let messages = [myPhoto(1, after: 0), myPhoto(nil, after: 60, status: .sending)]
        #expect(stackIDs(messages).isEmpty)
    }

    @Test("An edited caption under a stack shows the Edited marker on its row")
    func stackCaptionCarriesEdited() {
        func photo(_ seq: UInt64, caption: String?, edited: Bool) -> ConversationMessage {
            ConversationMessage(
                id: MessageID(value: seq),
                senderID: me,
                content: .media([MediaAttachment(blobID: BlobID(data: Data([UInt8(seq)])), width: 300, height: 400, blurhash: nil)], caption: caption),
                date: base.addingTimeInterval(Double(seq) * 0.5),
                unreadSeq: seq,
                lastEditedTs: edited ? base : nil
            )
        }
        let items = ChatItem.from([photo(1, caption: nil, edited: false), photo(2, caption: "sunrise", edited: true)], selfUserID: me)
        let captionRow = items.compactMap { item -> ChatMessage? in
            guard case .message(let row) = item, case .text(let text) = row.content, text == "sunrise" else { return nil }
            return row
        }.first
        #expect(captionRow?.isEdited == true)
    }
}
