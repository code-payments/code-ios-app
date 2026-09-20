//
//  ChatDraftStoreTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("Chat draft store")
struct ChatDraftStoreTests {

    private let owner = try! PublicKey(Data(repeating: 7, count: 32))

    /// A fresh, empty directory standing in for the session's Application Support folder.
    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("drafts-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func conversationID(_ byte: UInt8) -> ConversationID {
        ConversationID(data: Data(repeating: byte, count: 32))
    }

    private var replyTarget: ChatDraft.ReplyTarget {
        ChatDraft.ReplyTarget(
            messageID: 42,
            stableID: "9f1a6d5f-7c8e-4b21-9f3e-2b0b4d1e9a0b",
            authorName: "Ana",
            authorID: UUID(uuidString: "8B3D4E1A-0000-4000-8000-00000000002A"),
            snippet: "are we still on for 5?",
            kind: .text
        )
    }

    @Test("A saved draft is readable back")
    func savedDraftIsReadable() throws {
        let store = ChatDraftStore(directory: try makeDirectory(), owner: owner)
        let id = conversationID(1)

        store.save(ChatDraft(text: "half a thought", replyTarget: nil), for: id)

        #expect(store.draft(for: id)?.text == "half a thought")
    }

    @Test("A chat never typed in has no draft")
    func unknownChatHasNoDraft() throws {
        let store = ChatDraftStore(directory: try makeDirectory(), owner: owner)
        #expect(store.draft(for: conversationID(2)) == nil)
    }

    @Test("A flushed draft survives a new store over the same directory")
    func draftSurvivesReload() throws {
        let directory = try makeDirectory()
        let id = conversationID(3)

        let store = ChatDraftStore(directory: directory, owner: owner)
        store.save(ChatDraft(text: "see you at 5 ", replyTarget: replyTarget), for: id)
        store.flush()

        let reloaded = ChatDraftStore(directory: directory, owner: owner)
        let draft = try #require(reloaded.draft(for: id))
        #expect(draft.text == "see you at 5 ")
        #expect(draft.replyTarget == replyTarget)
    }

    @Test("The debounced write lands without an explicit flush")
    func debouncedWriteLands() async throws {
        let directory = try makeDirectory()
        let id = conversationID(4)

        let store = ChatDraftStore(directory: directory, owner: owner)
        store.save(ChatDraft(text: "on my way", replyTarget: nil), for: id)

        // Polled rather than slept past: the debounce is 300 ms of wall time
        // plus however long the write waits to be scheduled, which on a loaded
        // machine outruns any fixed multiple of the interval.
        try await waitUntil(pollInterval: .milliseconds(25)) {
            ChatDraftStore(directory: directory, owner: owner).draft(for: id)?.text == "on my way"
        }
    }

    @Test("Text is stored verbatim, whitespace and all")
    func textIsVerbatim() throws {
        let directory = try makeDirectory()
        let id = conversationID(5)

        let store = ChatDraftStore(directory: directory, owner: owner)
        store.save(ChatDraft(text: "  thinking about it  ", replyTarget: nil), for: id)
        store.flush()

        #expect(ChatDraftStore(directory: directory, owner: owner).draft(for: id)?.text == "  thinking about it  ")
    }

    @Test("Saving whitespace with no reply target removes the row rather than storing it")
    func emptyMeansDeleted() throws {
        let store = ChatDraftStore(directory: try makeDirectory(), owner: owner)
        let id = conversationID(6)

        store.save(ChatDraft(text: "never mind", replyTarget: nil), for: id)
        store.save(ChatDraft(text: "   ", replyTarget: nil), for: id)

        #expect(store.draft(for: id) == nil)
    }

    @Test("Whitespace with a reply target is still a draft")
    func bareReplyTargetIsADraft() throws {
        let store = ChatDraftStore(directory: try makeDirectory(), owner: owner)
        let id = conversationID(7)

        store.save(ChatDraft(text: "  ", replyTarget: replyTarget), for: id)

        let draft = try #require(store.draft(for: id))
        #expect(draft.text == "  ")
        #expect(draft.replyTarget == replyTarget)
    }

    @Test("Removing a draft clears it from disk too")
    func removeClearsDisk() throws {
        let directory = try makeDirectory()
        let id = conversationID(8)

        let store = ChatDraftStore(directory: directory, owner: owner)
        store.save(ChatDraft(text: "leaving anyway", replyTarget: nil), for: id)
        store.flush()
        store.remove(for: id)
        store.flush()

        #expect(ChatDraftStore(directory: directory, owner: owner).draft(for: id) == nil)
    }

    @Test("The file is owner-scoped, following the SQLite store's own naming")
    func fileNameIsOwnerScoped() throws {
        let directory = try makeDirectory()

        let store = ChatDraftStore(directory: directory, owner: owner)
        store.save(ChatDraft(text: "one", replyTarget: nil), for: conversationID(9))
        store.flush()

        let written = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(written == ["flipcash-\(owner.base58)-drafts.json"])
    }

    /// One Application Support directory serves every account on the device, so an unscoped file
    /// would hand the next account the previous one's half-typed messages.
    @Test("Two accounts sharing a directory do not see each other's drafts")
    func draftsAreScopedToTheOwner() throws {
        let directory = try makeDirectory()
        let other = try PublicKey(Data(repeating: 8, count: 32))
        let id = conversationID(10)

        let mine = ChatDraftStore(directory: directory, owner: owner)
        mine.save(ChatDraft(text: "for Ana", replyTarget: nil), for: id)
        mine.flush()

        #expect(ChatDraftStore(directory: directory, owner: other).draft(for: id) == nil)
        #expect(ChatDraftStore(directory: directory, owner: owner).draft(for: id)?.text == "for Ana")
    }

    @Test("Drafts in different chats do not collide")
    func draftsAreKeyedPerChat() throws {
        let directory = try makeDirectory()

        let store = ChatDraftStore(directory: directory, owner: owner)
        store.save(ChatDraft(text: "for Ana", replyTarget: nil), for: conversationID(11))
        store.save(ChatDraft(text: "for Ben", replyTarget: nil), for: conversationID(12))
        store.flush()

        let reloaded = ChatDraftStore(directory: directory, owner: owner)
        #expect(reloaded.draft(for: conversationID(11))?.text == "for Ana")
        #expect(reloaded.draft(for: conversationID(12))?.text == "for Ben")
    }

    @Test("A group's shorter chat id round-trips as a key")
    func groupIDRoundTrips() throws {
        let directory = try makeDirectory()
        let group = ConversationID(data: Data(repeating: 13, count: 16))

        let store = ChatDraftStore(directory: directory, owner: owner)
        store.save(ChatDraft(text: "anyone about?", replyTarget: nil), for: group)
        store.flush()

        #expect(ChatDraftStore(directory: directory, owner: owner).draft(for: group)?.text == "anyone about?")
    }

    @Test("A corrupt file leaves an empty store rather than failing the session")
    func corruptFileIsSurvivable() throws {
        let directory = try makeDirectory()
        try Data("not json".utf8).write(
            to: directory.appendingPathComponent("flipcash-\(owner.base58)-drafts.json")
        )

        let store = ChatDraftStore(directory: directory, owner: owner)
        #expect(store.draft(for: conversationID(14)) == nil)

        store.save(ChatDraft(text: "still works", replyTarget: nil), for: conversationID(14))
        store.flush()
        #expect(ChatDraftStore(directory: directory, owner: owner).draft(for: conversationID(14))?.text == "still works")
    }
}
