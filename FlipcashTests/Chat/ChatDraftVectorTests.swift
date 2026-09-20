//
//  ChatDraftVectorTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

/// `test-vectors/chat_draft.json`. Synced copy — a failure is fixed in the canonical fixture and
/// re-synced to both platforms, never edited here.
///
/// Each vector is a sequence of composer actions and the draft the store must hold once the screen
/// goes away. The actions run against the real `ComposerModel` and the real `ChatDraftStore`, wired
/// the way `ConversationScreen` wires them, so the vector exercises the shipping path rather than a
/// restatement of it.
@MainActor
@Suite("Chat draft vectors")
struct ChatDraftVectorTests {

    private let owner = try! PublicKey(Data(repeating: 7, count: 32))

    private final class BundleToken {}

    struct Target: Decodable, Equatable {
        let messageId: String
        let author: String
        let snippet: String
    }

    struct Action: Decodable {
        let op: String
        let text: String?
        /// Present but null for `reply` clearing the strip, which is why it is doubly optional.
        let target: Target??
    }

    struct Draft: Decodable {
        let text: String
        let replyTarget: Target?
    }

    struct Vector: Decodable {
        let name: String
        let actions: [Action]
        let draft: Draft?
        let note: String
    }

    struct Fixture: Decodable {
        let algorithm: String
        let vectors: [Vector]
    }

    private func loadFixture() throws -> Fixture {
        let bundle = Bundle(for: BundleToken.self)
        let url = try #require(bundle.url(forResource: "chat_draft", withExtension: "json"))
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    /// The fixture's message id is a uuid, which is the shape of an iOS transcript row's stable id
    /// rather than of a `MessageID`. It maps onto `stableID`, and the numeric id the send would use
    /// is a stand-in the vectors never look at.
    private func composerTarget(_ target: Target) -> ComposerModel.ReplyTarget {
        ComposerModel.ReplyTarget(
            messageID: MessageID(value: 1),
            stableID: target.messageId,
            authorName: target.author,
            authorID: nil,
            snippet: target.snippet
        )
    }

    @Test func draftsMatchTheCrossPlatformVectors() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("draft-vectors-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        for (index, vector) in try loadFixture().vectors.enumerated() {
            let store = ChatDraftStore(directory: directory, owner: owner)
            let conversationID = ConversationID(data: Data(repeating: UInt8(index), count: 32))
            let composer = ComposerModel()

            for action in vector.actions {
                switch action.op {
                case "type":
                    composer.draft = action.text ?? ""
                case "reply":
                    if let target = action.target.flatMap({ $0 }) {
                        composer.beginReplying(to: composerTarget(target))
                    } else {
                        composer.endReplying()
                    }
                case "send":
                    // The bottom bar's own order: nothing leaves without a submission, and the
                    // field clears before the send is dispatched.
                    if composer.submission != nil { composer.clear() }
                case "edit":
                    composer.beginEditing(
                        messageID: MessageID(value: 2),
                        stableID: "2",
                        currentText: action.text ?? ""
                    )
                case "cancelEdit":
                    composer.endEditing()
                case "leave":
                    store.save(composer.persistableDraft, for: conversationID)
                    store.flush()
                default:
                    Issue.record("vector `\(vector.name)` uses unknown op `\(action.op)`")
                }
            }

            let actual = ChatDraftStore(directory: directory, owner: owner).draft(for: conversationID)

            guard let expected = vector.draft else {
                #expect(actual == nil, "vector `\(vector.name)`: \(vector.note)")
                continue
            }

            guard let draft = actual else {
                Issue.record("vector `\(vector.name)` stored no draft: \(vector.note)")
                continue
            }
            #expect(draft.text == expected.text, "vector `\(vector.name)`: \(vector.note)")

            guard let expectedTarget = expected.replyTarget else {
                #expect(draft.replyTarget == nil, "vector `\(vector.name)`: \(vector.note)")
                continue
            }

            guard let target = draft.replyTarget else {
                Issue.record("vector `\(vector.name)` stored no reply target: \(vector.note)")
                continue
            }
            #expect(target.stableID == expectedTarget.messageId, "vector `\(vector.name)`: \(vector.note)")
            #expect(target.authorName == expectedTarget.author, "vector `\(vector.name)`: \(vector.note)")
            #expect(target.snippet == expectedTarget.snippet, "vector `\(vector.name)`: \(vector.note)")
        }
    }
}
