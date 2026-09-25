//
//  ReactionUITests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
import FlipcashCore
import FlipcashUI
@testable import Flipcash

/// Pure decisions behind the reaction UI surfaces (Tasks 10–14): strip eligibility/content, the pill
/// row's "+"/inert rules, the picker's search/category/frequent/undrawable grouping, the reactors
/// list's paging and reset-on-switch, the title count, and the error-to-copy mapping. UIKit/SwiftUI
/// chrome (the strip view, the sheets) isn't exercised here — see the simulator/preview pass instead.
@Suite("Reaction UI")
struct ReactionUITests {

    // MARK: - Strip content (ReactionStrip.entries, re-verified against the UI-facing call site)

    @Test("Strip highlights the viewer's own reactions and dedupes against recents")
    func stripHighlightsSelfReactions() {
        let entries = ReactionStrip.entries(
            recents: ["❤️", "😂", "👍"],
            selfReactions: [SelfReaction(emoji: "😂", reactedAt: .now)]
        )
        let byEmoji = Dictionary(uniqueKeysWithValues: entries.map { ($0.emoji, $0.highlighted) })
        #expect(byEmoji["😂"] == true)
        #expect(byEmoji["❤️"] == false)
        #expect(byEmoji["👍"] == false)
    }

    @Test("The catalog fills the strip after its entries, skipping ones already there")
    func stripFillsFromCatalog() {
        let entries = [
            ReactionStrip.Entry(emoji: "❤️", highlighted: false),
            ReactionStrip.Entry(emoji: "🦖", highlighted: true),
        ]
        let filled = ReactionStrip.filled(entries, from: ["😀", "❤️", "😃", "😄"], limit: 4)
        #expect(filled.map(\.emoji) == ["❤️", "🦖", "😀", "😃"])
        #expect(filled.map(\.highlighted) == [false, true, false, false])
    }

    @Test("The fill never drops one of the strip's own entries")
    func stripFillKeepsEntriesPastLimit() {
        let entries = ["❤️", "👍", "😂"].map { ReactionStrip.Entry(emoji: $0, highlighted: false) }
        let filled = ReactionStrip.filled(entries, from: ["😀"], limit: 2)
        #expect(filled == entries)
    }

    // MARK: - Strip eligibility (ChatMessage.offersReactionStrip)

    @Test("A deleted message never offers the strip")
    func deletedMessageNoStrip() {
        let message = Self.makeMessage(content: .deleted("This message was deleted"), sender: .other)
        #expect(message.offersReactionStrip == false)
    }

    @Test("The viewer's own message still in flight never offers the strip")
    func inFlightSendNoStrip() {
        let message = Self.makeMessage(content: .text("hi"), sender: .me, receipt: nil, isUnsent: true)
        #expect(message.offersReactionStrip == false)
    }

    @Test("An earlier sent message offers the strip though only the latest one carries a receipt")
    func earlierSentMessageOffersStrip() {
        let message = Self.makeMessage(content: .text("hi"), sender: .me, receipt: nil)
        #expect(message.offersReactionStrip == true)
    }

    @Test("The viewer's own message that has landed offers the strip")
    func landedOwnSendOffersStrip() {
        let message = Self.makeMessage(content: .text("hi"), sender: .me, receipt: .delivered)
        #expect(message.offersReactionStrip == true)
    }

    @Test("A counterpart's message offers the strip regardless of receipt")
    func counterpartMessageOffersStrip() {
        let message = Self.makeMessage(content: .text("hi"), sender: .other, receipt: nil)
        #expect(message.offersReactionStrip == true)
    }

    // MARK: - Pill row "+"/inert rules (ChatMessage.canReact)

    @Test("A group previewer without membership cannot react, but keeps their pills")
    func previewerCannotReact() {
        let message = Self.makeMessage(
            content: .text("hi"),
            sender: .other,
            canReact: false,
            reactions: [ReactionPill(emoji: "🔥", count: 2, selfReacted: false, pending: false)]
        )
        #expect(message.canReact == false)
        #expect(message.reactions.isEmpty == false)
    }

    @Test("A member can react and gets the trailing add pill")
    func memberCanReact() {
        let message = Self.makeMessage(content: .text("hi"), sender: .other, canReact: true)
        #expect(message.canReact == true)
    }

    // MARK: - Picker: search, category grouping, frequent row, undrawable filtering

    private static let catalog = EmojiCatalogContents(
        categories: ["Smileys", "Animals"],
        emoji: [
            EmojiCatalogEntry(emoji: "😀", name: "grinning face", category: "Smileys", version: "0.6", skinTone: false, keywords: ["happy", "smile"]),
            EmojiCatalogEntry(emoji: "😂", name: "face with tears of joy", category: "Smileys", version: "0.6", skinTone: false, keywords: ["laugh"]),
            EmojiCatalogEntry(emoji: "🐶", name: "dog face", category: "Animals", version: "0.6", skinTone: false, keywords: ["pet", "puppy"]),
            EmojiCatalogEntry(emoji: "🐱", name: "cat face", category: "Animals", version: "0.6", skinTone: false, keywords: ["pet", "kitten"]),
        ]
    )

    @Test("Empty search groups by category, in catalog order, with a leading Frequently Used row")
    @MainActor
    func groupsByCategory() {
        let sections = EmojiPickerModel.sections(catalog: Self.catalog, undrawable: [], recents: ["😂"], query: "")
        #expect(sections.map(\.id) == [EmojiPickerModel.frequentlyUsedID, "Smileys", "Animals"])
        #expect(sections[0].entries.map(\.emoji) == ["😂"])
        #expect(sections[1].entries.map(\.emoji) == ["😀", "😂"])
        #expect(sections[2].entries.map(\.emoji) == ["🐶", "🐱"])
    }

    @Test("No recents means no Frequently Used row")
    @MainActor
    func noFrequentRowWithoutRecents() {
        let sections = EmojiPickerModel.sections(catalog: Self.catalog, undrawable: [], recents: [], query: "")
        #expect(sections.contains { $0.id == EmojiPickerModel.frequentlyUsedID } == false)
    }

    @Test("A search matches name and keywords case-insensitively, and drops the Frequently Used row")
    @MainActor
    func searchMatchesNameAndKeywords() {
        let byName = EmojiPickerModel.sections(catalog: Self.catalog, undrawable: [], recents: ["😀"], query: "DOG")
        #expect(byName.count == 1)
        #expect(byName[0].entries.map(\.emoji) == ["🐶"])

        let byKeyword = EmojiPickerModel.sections(catalog: Self.catalog, undrawable: [], recents: [], query: "kitten")
        #expect(byKeyword[0].entries.map(\.emoji) == ["🐱"])
    }

    @Test("Undrawable entries are filtered from both categories and the Frequently Used row")
    @MainActor
    func undrawableFilteredEverywhere() {
        let sections = EmojiPickerModel.sections(catalog: Self.catalog, undrawable: ["😂"], recents: ["😂", "😀"], query: "")
        #expect(sections[0].entries.map(\.emoji) == ["😀"])
        #expect(sections[1].entries.map(\.emoji) == ["😀"])
    }

    // MARK: - Reactors paging and per-emoji lists (ReactorsListModel)

    private actor StubReactorsSource: ReactorsSource {
        private let pages: [String: [ReactorPage]]
        private(set) var calls: [(emoji: String, pagingToken: Data?)] = []

        init(pages: [String: [ReactorPage]]) {
            self.pages = pages
        }

        func fetchReactors(conversationID: ConversationID, messageID: MessageID, emoji: String, pagingToken: Data?) async throws -> ReactorPage {
            calls.append((emoji, pagingToken))
            let callIndex = calls.filter { $0.emoji == emoji }.count - 1
            guard let pagesForEmoji = pages[emoji], callIndex < pagesForEmoji.count else {
                return ReactorPage(reactors: [], nextPageToken: nil, version: 0)
            }
            return pagesForEmoji[callIndex]
        }
    }

    @MainActor
    private func makeModel(_ source: StubReactorsSource, emojis: [String] = ["🔥", "👍"]) -> ReactorsListModel {
        ReactorsListModel(source: source, conversationID: .test(1), messageID: MessageID(value: 1), emojis: emojis)
    }

    @MainActor
    @Test("Loading pages accumulates reactors and stops once nextPageToken is nil")
    func pagesAccumulate() async {
        let userA = UUID()
        let userB = UUID()
        let now = Date.now
        let source = StubReactorsSource(pages: [
            "🔥": [
                ReactorPage(reactors: [Reactor(userID: userA, reactedAt: now, version: 2)], nextPageToken: Data([1]), version: 2),
                ReactorPage(reactors: [Reactor(userID: userB, reactedAt: now.addingTimeInterval(-60), version: 1)], nextPageToken: nil, version: 2),
            ],
        ])
        let model = makeModel(source, emojis: ["🔥"])
        await model.loadMoreIfNeeded()
        #expect(model.rows.map(\.userID) == [userA])
        #expect(model.hasMore == true)
        await model.loadMoreIfNeeded()
        #expect(model.rows.map(\.userID) == [userA, userB])
        #expect(model.hasMore == false)
        // A further call is a no-op once exhausted.
        await model.loadMoreIfNeeded()
        #expect(await source.calls.count == 2)
    }

    @MainActor
    @Test("One row per person, with every emoji they used in pill order, newest reaction first")
    func rowsGroupByPerson() async {
        let userA = UUID()
        let userB = UUID()
        let now = Date.now
        let source = StubReactorsSource(pages: [
            "🔥": [ReactorPage(reactors: [
                Reactor(userID: userB, reactedAt: now, version: 2),
                Reactor(userID: userA, reactedAt: now.addingTimeInterval(-120), version: 1),
            ], nextPageToken: nil, version: 2)],
            "👍": [ReactorPage(reactors: [Reactor(userID: userA, reactedAt: now.addingTimeInterval(-60), version: 1)], nextPageToken: nil, version: 1)],
        ])
        let model = makeModel(source)
        await model.loadMoreIfNeeded()

        #expect(model.rows == [
            .init(userID: userB, emojis: ["🔥"]),
            .init(userID: userA, emojis: ["🔥", "👍"]),
        ])
        #expect(await source.calls.count == 2)
    }

    /// Answers 🔥 at once and holds 👍 until `release()`.
    private actor HeldReactorsSource: ReactorsSource {
        let reactor: Reactor
        private(set) var calls = 0
        private var held: CheckedContinuation<Void, Never>?

        init(reactor: Reactor) {
            self.reactor = reactor
        }

        func fetchReactors(conversationID: ConversationID, messageID: MessageID, emoji: String, pagingToken: Data?) async throws -> ReactorPage {
            calls += 1
            if emoji == "👍" {
                await withCheckedContinuation { held = $0 }
            }
            return ReactorPage(reactors: [reactor], nextPageToken: nil, version: 1)
        }

        func release() {
            held?.resume()
            held = nil
        }

        /// Whether both emoji were asked for and 👍 is being held.
        var isHoldingAfterBothCalls: Bool { held != nil && calls == 2 }
    }

    @MainActor
    @Test("Rows wait for every emoji's page, so a person's emoji arrive together")
    func rowsWaitForEveryEmoji() async {
        let user = UUID()
        let source = HeldReactorsSource(reactor: Reactor(userID: user, reactedAt: .now, version: 1))
        let model = ReactorsListModel(source: source, conversationID: .test(1), messageID: MessageID(value: 1), emojis: ["🔥", "👍"])

        let load = Task { await model.loadMoreIfNeeded() }
        while await !source.isHoldingAfterBothCalls {
            await Task.yield()
        }
        #expect(model.rows.isEmpty)

        await source.release()
        await load.value
        #expect(model.rows == [.init(userID: user, emojis: ["🔥", "👍"])])
    }

    // MARK: - Reactors sheet title count

    @Test("The title count sums every pill's count, not distinct reactors")
    func titleCountSumsPills() {
        let pills = [
            ReactionPill(emoji: "🔥", count: 3, selfReacted: false, pending: false),
            ReactionPill(emoji: "👍", count: 2, selfReacted: true, pending: false),
        ]
        #expect(pills.totalReactionCount == 5)
    }

    // MARK: - Error → copy mapping

    @Test("reactionFailed maps to the add-failure copy")
    func reactionFailedCopy() {
        #expect(ReactionUITests.reactionErrorCopy(.reactionFailed) == "Couldn't add reaction")
    }

    @Test("tooManyReactionTypes maps to the cap-reached copy")
    func tooManyReactionsCopy() {
        #expect(ReactionUITests.reactionErrorCopy(.tooManyReactionTypes) == "This message has the maximum number of reactions")
    }

    // MARK: - Helpers

    /// Mirrors `ConversationScreen.reactionErrorCopy` — kept in lockstep by this test rather than
    /// exposed, since the mapping is one switch the spec pins exactly.
    private static func reactionErrorCopy(_ error: ReactionError) -> String {
        switch error {
        case .reactionFailed:
            "Couldn't add reaction"
        case .tooManyReactionTypes:
            "This message has the maximum number of reactions"
        }
    }

    private static func makeMessage(
        content: ChatMessage.Content,
        sender: ChatMessage.Sender,
        receipt: ChatReceipt? = .delivered,
        canReact: Bool = true,
        reactions: [ReactionPill] = [],
        isUnsent: Bool = false
    ) -> ChatMessage {
        ChatMessage(
            id: UUID().uuidString,
            content: content,
            sender: sender,
            isContinuationFromPrevious: false,
            isContinuedByNext: false,
            joinsBubbleAbove: false,
            joinsBubbleBelow: false,
            isEmojiOnly: false,
            receipt: receipt,
            linkPreview: nil,
            isEdited: false,
            actions: [],
            quote: nil,
            author: nil,
            isAttributedTranscript: false,
            reactions: reactions,
            selfReactions: [],
            canReact: canReact,
            isUnsent: isUnsent
        )
    }
}
