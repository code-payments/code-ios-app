//
//  ShareRecipientsTests.swift
//  FlipcashCoreTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Testing
@testable import FlipcashCore

@Suite("Share recipients")
struct ShareRecipientsTests {

    private static func id(_ n: UInt8) -> ConversationID {
        ConversationID(data: Data(repeating: n, count: 32))
    }

    @Test("Toggling selects, then deselects")
    func toggle() {
        var selection = ShareRecipientSelection()
        #expect(selection.toggle(Self.id(1)) == .selected)
        #expect(selection.contains(Self.id(1)))
        #expect(selection.toggle(Self.id(1)) == .deselected)
        #expect(selection.isEmpty)
    }

    @Test("Selection keeps pick order and stops at the limit")
    func limit() {
        var selection = ShareRecipientSelection()
        for n in 1...UInt8(ShareRecipientSelection.limit) { selection.toggle(Self.id(n)) }
        #expect(selection.isFull)
        #expect(selection.toggle(Self.id(99)) == .limitReached)
        #expect(selection.ids.count == ShareRecipientSelection.limit)
        #expect(selection.ids.first == Self.id(1))
        #expect(selection.toggle(Self.id(2)) == .deselected)
        #expect(selection.toggle(Self.id(99)) == .selected)
    }

    @Test("Select is idempotent and retain drops unavailable ids")
    func selectAndRetain() {
        var selection = ShareRecipientSelection()
        selection.select(Self.id(1))
        selection.select(Self.id(1))
        selection.select(Self.id(2))
        #expect(selection.ids == [Self.id(1), Self.id(2)])
        selection.retain([Self.id(2)])
        #expect(selection.ids == [Self.id(2)])
    }

    @Test("Progress retries only what has not been sent")
    func progress() {
        let ids = [Self.id(1), Self.id(2), Self.id(3)]
        var progress = ShareSendProgress(recipients: ids)
        #expect(progress.remaining == ids)
        progress.markSent(ids[0])
        progress.markFailed(ids[1], message: "x", canRetry: true)
        progress.markFailed(ids[2], message: "y", canRetry: false)
        #expect(progress.remaining == [ids[1]])
        #expect(progress.failed == [ids[1], ids[2]])
        #expect(!progress.isComplete)
        #expect(!progress.isStuck)
        progress.markSent(ids[1])
        #expect(progress.isStuck)
        #expect(progress.remaining.isEmpty)
    }

    @Test("Progress is complete when every chat is sent")
    func complete() {
        var progress = ShareSendProgress(recipients: [Self.id(1)])
        progress.markSent(Self.id(1))
        #expect(progress.isComplete)
        #expect(!progress.isStuck)
    }

    private static func chat(_ n: UInt8, _ title: String) -> Conversation {
        Conversation(id: id(n), members: [], lastMessage: nil, lastActivity: Date(timeIntervalSince1970: 0), type: .group, title: title)
    }

    private static let chats = [chat(1, "Zoë Park"), chat(2, "Book club"), chat(3, "ZOLA")]
    private static func name(_ c: Conversation) -> String { c.title ?? "" }

    @Test("Search ignores case and diacritics and keeps order")
    func search() {
        let hits = ShareChatList.filter(Self.chats, query: " zo ", name: Self.name).map(\.id)
        #expect(hits == [Self.id(1), Self.id(3)])
        #expect(ShareChatList.filter(Self.chats, query: "  ", name: Self.name).count == 3)
        #expect(ShareChatList.filter(Self.chats, query: "nope", name: Self.name).isEmpty)
    }

    @Test("Sections lead with the suggestion and do not repeat it")
    func sections() {
        let sections = ShareChatList.sections(Self.chats, query: "", suggested: Self.id(2), name: Self.name)
        #expect(sections.suggested == [Self.id(2)])
        #expect(sections.recent == [Self.id(1), Self.id(3)])
        #expect(!sections.isSearching)
    }

    @Test("No suggestion omits the section; searching flattens it")
    func sectionsWithoutSuggestionOrWhileSearching() {
        let none = ShareChatList.sections(Self.chats, query: "", suggested: nil, name: Self.name)
        #expect(none.suggested.isEmpty)
        #expect(none.recent.count == 3)
        let searching = ShareChatList.sections(Self.chats, query: "book", suggested: Self.id(2), name: Self.name)
        #expect(searching.suggested.isEmpty)
        #expect(searching.recent == [Self.id(2)])
        #expect(searching.isSearching)
    }
}
