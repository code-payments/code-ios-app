//
//  ChatMarkUnreadTests.swift
//  FlipcashTests
//

import Testing
import Foundation
import SwiftUI
import UIKit
import FlipcashCore
import FlipcashStore
import FlipcashUI
@testable import Flipcash

/// The chat mark-unread spec's test table (`docs/specs/chat-mark-unread.md` in the orchestrator),
/// one test per row, numbered as there.
@MainActor
@Suite("Chat mark unread")
struct ChatMarkUnreadTests {

    private let me = UUID()
    private let them = UUID()

    // MARK: - Fixtures

    private func message(_ id: UInt64) -> ConversationMessage {
        ConversationMessage(
            id: MessageID(value: id),
            senderID: them,
            content: .text("m\(id)"),
            date: Date(timeIntervalSince1970: TimeInterval(id)),
            unreadSeq: id
        )
    }

    /// A tip DM whose newest message is `last` and whose READ sits at `pointer`: read when they match.
    private func chat(
        _ n: UInt8,
        pointer: UInt64,
        last: UInt64 = 5,
        type: ConversationType = .tipDm,
        muted: Bool = false
    ) -> Conversation {
        Conversation(
            id: .test(n),
            members: [
                ConversationMember(userID: me, displayName: "", readPointer: MessageID(value: pointer)),
                ConversationMember(userID: them, displayName: "Them"),
            ],
            lastMessage: message(last),
            lastActivity: Date(timeIntervalSince1970: TimeInterval(1_000 - Int(n))),
            type: type,
            viewerState: muted ? ConversationViewerState(mute: .forever, version: 1) : nil
        )
    }

    private struct Fixture {
        let mock: MockConversations
        let controller: ConversationController
        let marks: LocalChatMarkedUnreadStore
        let archive: ChatArchiveStore
        let database: Database
    }

    private func fixture(feed: [Conversation], groups: [Conversation] = []) async throws -> Fixture {
        let mock = MockConversations()
        mock.feed = feed
        mock.groupFeed = groups
        let database = try Database.makeTemp().database
        let controller = ConversationController(
            fetching: mock, membership: mock, viewerSettings: mock, messaging: mock, streaming: mock,
            contactNaming: MockDMContactNaming(),
            database: database,
            owner: .generate()!, selfUserID: me
        )
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("marks-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let owner = try PublicKey(Data(repeating: 7, count: 32))
        let archive = ChatArchiveStore(directory: directory, owner: owner)
        let marks = LocalChatMarkedUnreadStore(directory: directory, owner: owner)
        controller.chatArchive = archive
        controller.chatMarkedUnread = marks
        await controller.loadFeed()
        if !groups.isEmpty { await controller.loadGroupFeed() }
        return Fixture(mock: mock, controller: controller, marks: marks, archive: archive, database: database)
    }

    private func pointer(_ controller: ConversationController, _ n: UInt8) -> MessageID? {
        controller.conversation(withID: .test(n))?.selfReadPointer(for: me)
    }

    /// Lets any read-pointer RPC the call queued go out, so "no RPC" is checked after it would have.
    private func settle(_ controller: ConversationController) async throws {
        try await waitUntil { controller.readPointerSyncTasks.isEmpty }
    }

    // MARK: - Rows

    @Test("1: Mark as Unread on a read chat marks it, badges it once and sends nothing")
    func markUnreadOnReadChat() async throws {
        let f = try await fixture(feed: [chat(1, pointer: 5)])
        #expect(f.controller.readAction(for: chat(1, pointer: 5)) == .markUnread)
        #expect(f.controller.unreadChatListCount == 0)

        f.controller.markUnread(.test(1), source: .swipe)

        #expect(f.marks.markedIDs == [.test(1)])
        // No unread messages, so the row draws the no-count state: unread with no count.
        #expect(f.controller.chatListUnread(for: chat(1, pointer: 5)) == .unknown)
        #expect(f.controller.chatListProjection.unreadChip == [.test(1)])
        #expect(f.controller.unreadChatListCount == 1)
        try await settle(f.controller)
        #expect(f.mock.markedRead.isEmpty)
    }

    @Test("2: Mark as Read on a marked chat with nothing unread clears the mark and sends nothing")
    func markReadOnMarkedChat() async throws {
        let f = try await fixture(feed: [chat(1, pointer: 5)])
        f.marks.mark(.test(1))
        #expect(f.controller.readAction(for: chat(1, pointer: 5)) == .markRead)

        f.controller.markRead(.test(1), source: .menu)

        #expect(f.marks.markedIDs.isEmpty)
        #expect(f.controller.unreadChatListCount == 0)
        try await settle(f.controller)
        #expect(f.mock.markedRead.isEmpty)
    }

    @Test("3: the swipe on a chat with 3 unread offers Mark as Read, which advances READ to the latest")
    func swipeOnUnreadChatReads() async throws {
        let f = try await fixture(feed: [chat(1, pointer: 2, last: 5)])
        let conversation = try #require(f.controller.conversation(withID: .test(1)))
        let action = try #require(f.controller.readAction(for: conversation))
        #expect(action == .markRead)

        f.controller.perform(action, on: .test(1), source: .swipe)

        #expect(pointer(f.controller, 1) == MessageID(value: 5))
        try await waitUntil { f.mock.markedRead == [MessageID(value: 5)] }
    }

    @Test("4: opening a marked chat clears its mark")
    func openingClearsMark() async throws {
        let f = try await fixture(feed: [chat(1, pointer: 5)])
        f.marks.mark(.test(1))

        f.controller.chatOpened(.test(1))

        #expect(f.marks.markedIDs.isEmpty)
    }

    @Test("5: a new message in a marked chat keeps the mark; the count shows and the badge counts it once")
    func newMessageKeepsMark() async throws {
        let f = try await fixture(feed: [chat(1, pointer: 5, last: 5)])
        f.marks.mark(.test(1))
        // The new message lands: stored, and the feed's last message moves past READ.
        try f.database.upsertConversationMessages([message(5), message(6)], conversationID: .test(1))
        f.mock.feed = [chat(1, pointer: 5, last: 6)]
        await f.controller.loadFeed()

        #expect(f.marks.markedIDs == [.test(1)])
        let updated = try #require(f.controller.conversation(withID: .test(1)))
        #expect(f.controller.chatListUnread(for: updated) == .count(1))
        #expect(f.controller.unreadChatListCount == 1)
    }

    @Test("6: archiving and unarchiving a marked chat keeps the mark throughout")
    func archiveKeepsMark() async throws {
        let f = try await fixture(feed: [chat(1, pointer: 5)])
        f.marks.mark(.test(1))

        f.controller.archive(.test(1))
        #expect(f.controller.isMarkedUnread(.test(1)))
        #expect(f.controller.archivedConversations.map(\.id) == [.test(1)])

        f.controller.unarchive(.test(1))
        #expect(f.controller.isMarkedUnread(.test(1)))
        #expect(f.controller.unreadChatListCount == 1)
    }

    @Test("7: leaving a marked group clears its mark")
    func leaveClearsMark() async throws {
        let f = try await fixture(feed: [], groups: [chat(9, pointer: 5, type: .group)])
        f.marks.mark(.test(9))

        try await f.controller.leave(conversationID: .test(9))

        #expect(f.marks.markedIDs.isEmpty)
    }

    @Test("8: marks are kept per account: another account sees none, and the same account sees its own again")
    func marksArePerAccount() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("marks-accounts-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let accountX = try PublicKey(Data(repeating: 8, count: 32))
        let accountY = try PublicKey(Data(repeating: 9, count: 32))

        LocalChatMarkedUnreadStore(directory: directory, owner: accountX).mark(.test(1))

        // Account switch: a store for Y over the same directory.
        #expect(LocalChatMarkedUnreadStore(directory: directory, owner: accountY).markedIDs.isEmpty)
        // Signing back in to X: a fresh store reads X's file.
        #expect(LocalChatMarkedUnreadStore(directory: directory, owner: accountX).markedIDs == [.test(1)])
    }

    @Test("9: Read All reads A, clears B, leaves C, keeps archived D marked, and counts 2")
    func readAll() async throws {
        let f = try await fixture(feed: [
            chat(1, pointer: 2, last: 5),   // A: unread
            chat(2, pointer: 5),            // B: marked
            chat(3, pointer: 5),            // C: read
            chat(4, pointer: 5),            // D: archived, marked
        ])
        f.marks.mark(.test(2))
        f.marks.mark(.test(4))
        f.controller.archive(.test(4))

        let count = f.controller.readAllChats()

        #expect(count == 2)
        #expect(pointer(f.controller, 1) == MessageID(value: 5))
        #expect(!f.controller.isMarkedUnread(.test(2)))
        #expect(pointer(f.controller, 3) == MessageID(value: 5))
        #expect(f.controller.isMarkedUnread(.test(4)))
        try await waitUntil { f.mock.markedRead == [MessageID(value: 5)] }
        try await settle(f.controller)
        // Only A had anything to send.
        #expect(f.mock.markedRead == [MessageID(value: 5)])
        #expect(f.controller.unreadChatListCount == 0)
    }

    @Test("10: with nothing unread in the main list, Read All is disabled")
    func readAllDisabledWhenNothingUnread() async throws {
        let f = try await fixture(feed: [chat(1, pointer: 5), chat(2, pointer: 5)])
        f.marks.mark(.test(2))
        f.controller.archive(.test(2))

        // An archived mark doesn't count toward the main list.
        #expect(!f.controller.hasUnreadInChatList)
    }

    @Test("11: cancelling the Read All dialog changes nothing")
    func readAllCancel() async throws {
        let f = try await fixture(feed: [chat(1, pointer: 2, last: 5), chat(2, pointer: 5)])
        f.marks.mark(.test(2))
        var confirmed = false
        let dialog = DialogItem.markAllChatsRead { confirmed = true }

        #expect(dialog.title == "Mark All Chats as Read?")
        #expect(dialog.subtitle == "Everyone in these chats will see that you've read their messages")
        #expect(dialog.actions.map(\.title) == ["Mark as Read", "Cancel"])
        let cancel = try #require(dialog.actions.first { $0.title == "Cancel" })
        cancel.action()

        #expect(!confirmed)
        #expect(pointer(f.controller, 1) == MessageID(value: 2))
        #expect(f.controller.isMarkedUnread(.test(2)))
        try await settle(f.controller)
        #expect(f.mock.markedRead.isEmpty)
    }

    @Test("12: a selection with an unread chat offers Read, and both end read")
    func selectionRead() async throws {
        let f = try await fixture(feed: [chat(1, pointer: 2, last: 5), chat(3, pointer: 5)])
        let ids: [ConversationID] = [.test(1), .test(3)]

        let toggle = f.controller.readToggle(for: ids)
        #expect(toggle == .read)
        #expect(toggle.title == "Read")
        f.controller.apply(toggle, to: ids)

        #expect(f.controller.readToggle(for: ids) == .unread)
        #expect(pointer(f.controller, 1) == MessageID(value: 5))
        #expect(f.marks.markedIDs.isEmpty)
    }

    @Test("13: a selection of read chats offers Unread, and both end marked")
    func selectionUnread() async throws {
        let f = try await fixture(feed: [chat(3, pointer: 5), chat(5, pointer: 5)])
        let ids: [ConversationID] = [.test(3), .test(5)]

        let toggle = f.controller.readToggle(for: ids)
        #expect(toggle == .unread)
        #expect(toggle.title == "Unread")
        f.controller.apply(toggle, to: ids)

        #expect(f.marks.markedIDs == [.test(3), .test(5)])
        #expect(ChatSelectionReadToggle(selectedUnread: []) == .readAll)
        #expect(ChatSelectionReadToggle.readAll.title == "Read All")
    }

    @Test("14: a muted and an unmuted chat offer Mute; one choice applies to both")
    func selectionMute() async throws {
        let f = try await fixture(feed: [chat(1, pointer: 5, muted: true), chat(2, pointer: 5)])
        let ids: [ConversationID] = [.test(1), .test(2)]

        #expect(f.controller.muteToggle(for: ids) == .mute)
        try await f.controller.mute(ids, .forever)

        #expect(f.mock.muted.map(\.conversationID) == ids)
    }

    @Test("15: a selection that is all muted offers Unmute, which unmutes both")
    func selectionUnmute() async throws {
        let f = try await fixture(feed: [chat(1, pointer: 5, muted: true), chat(2, pointer: 5, muted: true)])
        let ids: [ConversationID] = [.test(1), .test(2)]

        let mute = f.controller.muteToggle(for: ids)
        #expect(mute == .unmute)
        #expect(mute.title == "Unmute")
        try await f.controller.unmute(ids)

        #expect(f.mock.unmuted == ids)
    }

    @Test("16: archiving two shows one \"2 chats archived\" toast; Undo restores both")
    func selectionArchiveUndo() async throws {
        let f = try await fixture(feed: [chat(1, pointer: 5), chat(2, pointer: 5), chat(3, pointer: 5)])
        let ids: [ConversationID] = [.test(1), .test(2)]
        f.controller.archive(ids)
        #expect(f.controller.archivedConversations.map(\.id) == ids)
        #expect(f.controller.chatListConversations.map(\.id) == [.test(3)])
        #expect(ToastController.Toast.archivedChatsTitle(count: 2) == "2 chats archived")
        #expect(ToastController.Toast.archivedChatsTitle(count: 1) == "Chat archived")

        // The toast's Undo runs this.
        f.controller.unarchive(ids)

        #expect(f.controller.archivedConversations.isEmpty)
        #expect(f.controller.chatListConversations.map(\.id) == [.test(1), .test(2), .test(3)])
    }

    @Test("17: the long-press preview on an unread chat leaves READ and the unread state alone")
    func previewDoesNotRead() async throws {
        let f = try await fixture(feed: [chat(1, pointer: 2, last: 5)])
        try f.database.upsertConversationMessages((1...5).map(message), conversationID: .test(1))
        let conversation = try #require(f.controller.conversation(withID: .test(1)))

        #expect(f.controller.previewMessages(for: conversation).map(\.id.value) == [1, 2, 3, 4, 5])
        // Render the preview as the menu would, then let it go without a tap.
        let host = UIHostingController(rootView: ChatPreview(conversation: conversation).environment(f.controller))
        host.view.frame = CGRect(x: 0, y: 0, width: 340, height: 430)
        host.view.layoutIfNeeded()

        #expect(pointer(f.controller, 1) == MessageID(value: 2))
        #expect(f.controller.conversation(withID: .test(1))?.hasUnread(for: me) == true)
        try await settle(f.controller)
        #expect(f.mock.markedRead.isEmpty)
    }

    @Test("18: a chat still in Requests offers no read action and can't be marked")
    func requestsHaveNoReadActions() async throws {
        let f = try await fixture(feed: [])
        // A group the user hasn't joined: a request, not a member chat.
        let requested = chat(7, pointer: 5, type: .group)

        #expect(f.controller.readAction(for: requested) == nil)
        f.controller.markUnread(requested.id, source: .swipe)
        #expect(f.marks.markedIDs.isEmpty)
    }
}
