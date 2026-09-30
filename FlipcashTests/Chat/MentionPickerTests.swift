//
//  MentionPickerTests.swift
//  FlipcashTests
//

import Testing
import Foundation
import SwiftUI
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("Mention trigger")
struct MentionTriggerTests {

    private func query(_ text: String) -> String? {
        MentionTrigger.query(in: text, cursor: text.endIndex)?.text
    }

    @Test("An @ at the start of the text opens the picker")
    func atStart() {
        #expect(query("@") == "")
        #expect(query("@ma") == "ma")
    }

    @Test("An @ after whitespace opens the picker")
    func afterSpace() {
        #expect(query("hi @ma") == "ma")
        #expect(query("hi\n@ma") == "ma")
    }

    @Test("A fullwidth ＠ opens the picker")
    func fullwidth() {
        #expect(query("hi ＠ma") == "ma")
    }

    @Test("An @ inside a word never opens the picker")
    func insideWord() {
        #expect(query("a@b") == nil)
        #expect(query("a@") == nil)
    }

    @Test("Typing whitespace after the word closes the picker")
    func whitespaceCloses() {
        #expect(query("hi @ma ") == nil)
    }

    @Test("Deleting the @ closes the picker")
    func deletedTrigger() {
        #expect(query("hi ma") == nil)
    }

    @Test("Moving the cursor off the word closes the picker")
    func cursorMoved() {
        let text = "hi @ma there"
        #expect(MentionTrigger.query(in: text, cursor: text.endIndex) == nil)
        let beforeTrigger = text.index(text.startIndex, offsetBy: 3)
        #expect(MentionTrigger.query(in: text, cursor: beforeTrigger) == nil)
        let afterWord = text.index(text.startIndex, offsetBy: 6)
        #expect(MentionTrigger.query(in: text, cursor: afterWord)?.text == "ma")
    }

    @Test("A selection never opens the picker")
    func selectionNeverOpens() {
        let text = "hi @ma"
        let range = text.index(text.startIndex, offsetBy: 3)..<text.endIndex
        #expect(MentionTrigger.query(in: text, selection: TextSelection(range: range)) == nil)
        #expect(MentionTrigger.query(in: text, selection: nil) == nil)
        #expect(MentionTrigger.query(in: text, selection: TextSelection(insertionPoint: text.endIndex))?.text == "ma")
    }
}

@MainActor
@Suite("Mention insertion")
struct MentionInsertionTests {

    @Test("A pick replaces the word with @username and a trailing space")
    func trailingSpace() throws {
        let composer = ComposerModel()
        composer.draft = "hi @ma"
        composer.selection = TextSelection(insertionPoint: composer.draft.endIndex)

        composer.insertMention(username: "maria")

        #expect(composer.draft == "hi @maria ")
        #expect(composer.mentionQuery == nil)
        let cursor = try #require(composer.selection)
        #expect(MentionTrigger.query(in: composer.draft, selection: cursor) == nil)
    }

    @Test("A pick before an existing space reuses it and puts the cursor after it")
    func midText() throws {
        let text = "hi @ma there"
        let cursor = text.index(text.startIndex, offsetBy: 6)
        let query = try #require(MentionTrigger.query(in: text, cursor: cursor))

        let result = MentionTrigger.inserting(username: "maria", replacing: query, in: text)

        #expect(result.text == "hi @maria there")
        #expect(result.text[result.text.startIndex..<result.cursor] == "hi @maria ")
    }

    @Test("A pick before a newline reuses it instead of adding a space")
    func beforeNewline() throws {
        let text = "hi @ma\nthere"
        let cursor = text.index(text.startIndex, offsetBy: 6)
        let query = try #require(MentionTrigger.query(in: text, cursor: cursor))

        let result = MentionTrigger.inserting(username: "maria", replacing: query, in: text)

        #expect(result.text == "hi @maria\nthere")
        #expect(result.text[result.text.startIndex..<result.cursor] == "hi @maria\n")
    }

    @Test("A pick before a non-space character still adds the trailing space")
    func beforeNonSpace() throws {
        let text = "hi @ma,"
        let cursor = text.index(text.startIndex, offsetBy: 6)
        let query = try #require(MentionTrigger.query(in: text, cursor: cursor))

        let result = MentionTrigger.inserting(username: "maria", replacing: query, in: text)

        #expect(result.text == "hi @maria ,")
        #expect(result.text[result.text.startIndex..<result.cursor] == "hi @maria ")
    }
}

@MainActor
@Suite("Mention row cap")
struct MentionRowCapTests {

    private let rowHeight: CGFloat = 56
    private let divider: CGFloat = 1
    private let chrome: CGFloat = 16

    private func rows(replyOpen: Bool, room: CGFloat?) -> Int {
        MentionRowCap.rows(replyOpen: replyOpen, room: room, rowHeight: rowHeight, divider: divider, chrome: chrome)
    }

    @Test("Four rows with no reply open, three with one")
    func fullCounts() {
        #expect(rows(replyOpen: false, room: nil) == 4)
        #expect(rows(replyOpen: true, room: nil) == 3)
        #expect(rows(replyOpen: false, room: 400) == 4)
        #expect(rows(replyOpen: true, room: 320) == 3)
    }

    @Test("Two rows when the full list would leave the transcript under 120pt")
    func fallback() {
        // 4 rows = 224 + 3 dividers + 16 = 243pt; 300 - 243 = 57 < 120.
        #expect(rows(replyOpen: false, room: 300) == 2)
        // 3 rows = 168 + 2 dividers + 16 = 186pt; 300 - 186 = 114 < 120.
        #expect(rows(replyOpen: true, room: 300) == 2)
        // Exactly 120pt left keeps the full count.
        #expect(rows(replyOpen: false, room: 363) == 4)
    }

    @Test("List heights count a divider between rows and none after the last")
    func listHeights() {
        #expect(MentionListMetrics.listHeight(rows: 4) == 203)
        #expect(MentionListMetrics.listHeight(rows: 3) == 152)
        #expect(MentionListMetrics.listHeight(rows: 2) == 101)
        #expect(MentionListMetrics.listHeight(rows: 1) == 50)
        #expect(MentionListMetrics.listHeight(rows: 0) == 0)
    }
}

@MainActor
@Suite("Mention picker model")
struct MentionPickerModelTests {

    private let chatID = ConversationID(data: Data(repeating: 0x09, count: 32))

    @MainActor
    final class FakeSource: RosterSearchSource {
        var members: [ConversationMember] = []
        private(set) var prepareCount = 0
        private(set) var searches: [String] = []
        private var gate: CheckedContinuation<Void, Never>?
        private var outcome: Bool?

        func prepare(chatID: ConversationID) async -> Bool {
            prepareCount += 1
            if outcome == nil { await withCheckedContinuation { gate = $0 } }
            return outcome ?? false
        }

        /// Lets the refresh finish with `succeeding`, whether or not it has started waiting yet.
        func release(succeeding: Bool = true) {
            outcome = succeeding
            gate?.resume()
            gate = nil
        }

        func search(chatID: ConversationID, query: String, limit: Int) async throws -> [MemberMatch] {
            searches.append(query)
            return members.map { MemberMatch(member: $0, id: $0.userID!) }
        }
    }

    private func member(_ name: String, username: String?) -> ConversationMember {
        ConversationMember(userID: UUID(), displayName: name, username: username.flatMap(Username.init), version: 1)
    }

    @Test("A finished refresh re-runs the current query so new joiners appear")
    func refreshThenRequery() async throws {
        let source = FakeSource()
        source.members = [member("Érica", username: "erica")]
        let model = MentionPickerModel(source: source, chatID: chatID)

        model.update(query: "er")
        await model.searchTask?.value
        #expect(model.candidates.map(\.displayName) == ["Érica"])

        source.members.append(member("Erin", username: "erin"))
        source.release()
        await model.refreshTask?.value
        await model.searchTask?.value

        #expect(source.searches == ["er", "er"])
        #expect(model.candidates.map(\.displayName) == ["Érica", "Erin"])
    }

    @Test("A refresh that lands after the picker closed leaves it closed")
    func refreshAfterClose() async {
        let source = FakeSource()
        source.members = [member("Érica", username: "erica")]
        let model = MentionPickerModel(source: source, chatID: chatID)

        model.update(query: "er")
        await model.searchTask?.value
        model.update(query: nil)
        source.release()
        await model.refreshTask?.value
        await model.searchTask?.value

        #expect(source.searches == ["er"])
        #expect(model.candidates.isEmpty)
    }

    @Test("A failed refresh doesn't search again")
    func failedRefresh() async {
        let source = FakeSource()
        source.members = [member("Érica", username: "erica")]
        let model = MentionPickerModel(source: source, chatID: chatID)

        model.update(query: "er")
        await model.searchTask?.value
        source.members.append(member("Erin", username: "erin"))
        source.release(succeeding: false)
        await model.refreshTask?.value
        await model.searchTask?.value

        #expect(source.searches == ["er"])
        #expect(model.candidates.map(\.displayName) == ["Érica"])
    }

    @Test("The source is prepared once per visit, not on every query")
    func refreshOnce() async {
        let source = FakeSource()
        let model = MentionPickerModel(source: source, chatID: chatID)

        model.update(query: "m")
        model.update(query: nil)
        model.update(query: "ma")
        source.release()
        await model.refreshTask?.value

        #expect(source.prepareCount == 1)
    }

    @Test("Members without a username are not offered")
    func usernameRequired() async {
        let source = FakeSource()
        source.members = [member("Maria", username: "maria"), member("Mateo", username: nil)]
        let model = MentionPickerModel(source: source, chatID: chatID)

        model.update(query: "ma")
        await model.searchTask?.value

        #expect(model.candidates.map(\.displayName) == ["Maria"])
        source.release()
    }

    @Test("Closing the picker clears the candidates")
    func closeClears() async {
        let source = FakeSource()
        source.members = [member("Maria", username: "maria")]
        let model = MentionPickerModel(source: source, chatID: chatID)

        model.update(query: "ma")
        await model.searchTask?.value
        model.update(query: nil)

        #expect(model.candidates.isEmpty)
        source.release()
    }
}
