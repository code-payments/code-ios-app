//
//  FailedSendDraftsTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

/// The iOS-only half of the draft rules, deliberately outside `chat_draft.json`: a failed send has
/// no persisted record here — `SendStatus.failed` lives in memory for this session only — so the
/// text goes back to the draft store instead, and comes out again when a retry lands.
@MainActor
@Suite("Failed send drafts")
struct FailedSendDraftsTests {

    private func makeStore() throws -> ChatDraftStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("failed-sends-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return ChatDraftStore(directory: directory)
    }

    private let conversationID = ConversationID(data: Data(repeating: 1, count: 32))

    @Test("A send that fails puts its text back in the store")
    func failedSendRestoresTheDraft() throws {
        let store = try makeStore()
        let drafts = FailedSendDrafts(store: store)
        let clientMessageID = UUID()

        drafts.willSend(ChatDraft(text: "on my way", replyTarget: nil), clientMessageID: clientMessageID, in: conversationID)
        drafts.didFail(clientMessageID: clientMessageID)

        #expect(store.draft(for: conversationID)?.text == "on my way")
    }

    @Test("A send that fails restores the reply target with the text")
    func failedSendRestoresTheReplyTarget() throws {
        let store = try makeStore()
        let drafts = FailedSendDrafts(store: store)
        let clientMessageID = UUID()
        let target = ChatDraft.ReplyTarget(
            messageID: 7,
            stableID: "7",
            authorName: "Ana",
            authorID: nil,
            snippet: "are we still on for 5?",
            kind: .text
        )

        drafts.willSend(ChatDraft(text: "yes", replyTarget: target), clientMessageID: clientMessageID, in: conversationID)
        drafts.didFail(clientMessageID: clientMessageID)

        #expect(store.draft(for: conversationID)?.replyTarget == target)
    }

    @Test("A retry that succeeds takes the restored draft away again")
    func successfulRetryRemovesTheDraft() throws {
        let store = try makeStore()
        let drafts = FailedSendDrafts(store: store)
        let clientMessageID = UUID()

        drafts.willSend(ChatDraft(text: "on my way", replyTarget: nil), clientMessageID: clientMessageID, in: conversationID)
        drafts.didFail(clientMessageID: clientMessageID)
        drafts.didSucceed(clientMessageID: clientMessageID)

        #expect(store.draft(for: conversationID) == nil)
    }

    @Test("A send that succeeds first time never touches the store")
    func successfulSendLeavesTheStoreAlone() throws {
        let store = try makeStore()
        let drafts = FailedSendDrafts(store: store)
        store.save(ChatDraft(text: "typed while it was in flight", replyTarget: nil), for: conversationID)

        let clientMessageID = UUID()
        drafts.willSend(ChatDraft(text: "on my way", replyTarget: nil), clientMessageID: clientMessageID, in: conversationID)
        drafts.didSucceed(clientMessageID: clientMessageID)

        #expect(store.draft(for: conversationID)?.text == "typed while it was in flight")
    }

    @Test("A failure never overwrites a newer draft typed in the same chat")
    func failureDoesNotClobberANewerDraft() throws {
        let store = try makeStore()
        let drafts = FailedSendDrafts(store: store)
        let clientMessageID = UUID()

        drafts.willSend(ChatDraft(text: "on my way", replyTarget: nil), clientMessageID: clientMessageID, in: conversationID)
        store.save(ChatDraft(text: "actually, running late", replyTarget: nil), for: conversationID)
        drafts.didFail(clientMessageID: clientMessageID)

        #expect(store.draft(for: conversationID)?.text == "actually, running late")
    }

    @Test("A retry that succeeds keeps a draft typed since the write-back")
    func successKeepsADraftTypedSinceTheWriteBack() throws {
        let store = try makeStore()
        let drafts = FailedSendDrafts(store: store)
        let clientMessageID = UUID()

        drafts.willSend(ChatDraft(text: "on my way", replyTarget: nil), clientMessageID: clientMessageID, in: conversationID)
        drafts.didFail(clientMessageID: clientMessageID)
        store.save(ChatDraft(text: "second thoughts", replyTarget: nil), for: conversationID)
        drafts.didSucceed(clientMessageID: clientMessageID)

        #expect(store.draft(for: conversationID)?.text == "second thoughts")
    }

    @Test("A second failure of the same message does not stack up")
    func repeatedFailuresAreIdempotent() throws {
        let store = try makeStore()
        let drafts = FailedSendDrafts(store: store)
        let clientMessageID = UUID()

        drafts.willSend(ChatDraft(text: "on my way", replyTarget: nil), clientMessageID: clientMessageID, in: conversationID)
        drafts.didFail(clientMessageID: clientMessageID)
        drafts.didFail(clientMessageID: clientMessageID)
        drafts.didSucceed(clientMessageID: clientMessageID)

        #expect(store.draft(for: conversationID) == nil)
    }

    @Test("A message the unit never saw is left alone")
    func unknownMessageIsIgnored() throws {
        let store = try makeStore()
        let drafts = FailedSendDrafts(store: store)
        store.save(ChatDraft(text: "mine", replyTarget: nil), for: conversationID)

        drafts.didFail(clientMessageID: UUID())
        drafts.didSucceed(clientMessageID: UUID())

        #expect(store.draft(for: conversationID)?.text == "mine")
    }
}
