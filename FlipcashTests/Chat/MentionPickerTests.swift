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

    @Test("A pick mid-text keeps the text after the word and puts the cursor after the space")
    func midText() throws {
        let text = "hi @ma there"
        let cursor = text.index(text.startIndex, offsetBy: 6)
        let query = try #require(MentionTrigger.query(in: text, cursor: cursor))

        let result = MentionTrigger.inserting(username: "maria", replacing: query, in: text)

        #expect(result.text == "hi @maria  there")
        #expect(result.text[result.text.startIndex..<result.cursor] == "hi @maria ")
    }
}

@MainActor
@Suite("Mention row cap")
struct MentionRowCapTests {

    private let rowHeight: CGFloat = 56
    private let chrome: CGFloat = 16

    @Test("Four rows with no reply open, three with one")
    func fullCounts() {
        #expect(MentionRowCap.rows(replyOpen: false, room: nil, rowHeight: rowHeight, chrome: chrome) == 4)
        #expect(MentionRowCap.rows(replyOpen: true, room: nil, rowHeight: rowHeight, chrome: chrome) == 3)
        #expect(MentionRowCap.rows(replyOpen: false, room: 400, rowHeight: rowHeight, chrome: chrome) == 4)
        #expect(MentionRowCap.rows(replyOpen: true, room: 320, rowHeight: rowHeight, chrome: chrome) == 3)
    }

    @Test("Two rows when the full list would leave the transcript under 120pt")
    func fallback() {
        // 4 rows = 240pt; 300 - 240 = 60 < 120.
        #expect(MentionRowCap.rows(replyOpen: false, room: 300, rowHeight: rowHeight, chrome: chrome) == 2)
        // 3 rows = 184pt; 300 - 184 = 116 < 120.
        #expect(MentionRowCap.rows(replyOpen: true, room: 300, rowHeight: rowHeight, chrome: chrome) == 2)
        // Exactly 120pt left keeps the full count.
        #expect(MentionRowCap.rows(replyOpen: false, room: 360, rowHeight: rowHeight, chrome: chrome) == 4)
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
        private var released = false

        func prepare(chatID: ConversationID) async {
            prepareCount += 1
            guard !released else { return }
            await withCheckedContinuation { gate = $0 }
        }

        /// Lets the refresh finish, whether or not it has started waiting yet.
        func release() {
            released = true
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
        source.members = [member("Maria", username: "maria")]
        let model = MentionPickerModel(source: source, chatID: chatID)

        model.update(query: "ma")
        await model.searchTask?.value
        #expect(model.candidates.map(\.displayName) == ["Maria"])

        source.members.append(member("Marco", username: "marco"))
        source.release()
        await model.refreshTask?.value
        await model.searchTask?.value

        #expect(source.searches == ["ma", "ma"])
        #expect(model.candidates.map(\.displayName) == ["Maria", "Marco"])
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
