//
//  CardSuggestionModelTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
import FlipcashCore
import FlipcashUI
@testable import Flipcash

@MainActor
@Suite("Card suggestion")
struct CardSuggestionModelTests {

    // MARK: - Fixtures -

    private final class Source: LinkCardSource {
        var answers: [String: LinkCard.User.State] = [:]
        private(set) var asked: [String] = []

        func known(_ card: LinkCard) -> LinkCard.State? { nil }

        func states(for card: LinkCard) -> AsyncStream<LinkCard.State> {
            guard case .user(let user) = card, case .username(let username) = user.identity else {
                return AsyncStream { $0.finish() }
            }
            asked.append(username.value)
            let answer = answers[username.value] ?? .notFound
            return AsyncStream { continuation in
                continuation.yield(.user(answer))
                continuation.finish()
            }
        }
    }

    private static let jeffID = UserID()

    private static func person(_ id: UserID = jeffID, name: String = "Jeff", isOwn: Bool = false) -> LinkCard.User.State {
        .resolved(.init(
            userID: id,
            isOwn: isOwn,
            displayName: name,
            handle: "@jeff",
            joined: nil,
            imageData: nil,
            blurHash: nil
        ))
    }

    private static func model(_ source: Source, excluding: UserID? = nil) -> CardSuggestionModel {
        let model = CardSuggestionModel(debounce: .zero)
        model.connect(to: source, excluding: excluding)
        return model
    }

    private static func typed(_ text: String, into model: CardSuggestionModel) async {
        model.draftDidChange(text)
        await model.settle()
    }

    // MARK: - Detection -

    @Test("A handle in the middle of a sentence is a mention")
    func mentionInSentence() {
        #expect(CardSuggestionModel.mentionedHandle(in: "You should talk to @jeff. He's the man")?.value == "jeff")
    }

    @Test("A handle is matched case-insensitively, the way the server stores it")
    func mentionIsLowercased() {
        #expect(CardSuggestionModel.mentionedHandle(in: "ask @Jeff")?.value == "jeff")
    }

    @Test("An email address is not a mention")
    func emailIsNotMention() {
        #expect(CardSuggestionModel.mentionedHandle(in: "mail bob@example.com") == nil)
    }

    @Test("A lone @ or a one-letter handle is not a mention")
    func tooShortIsNotMention() {
        #expect(CardSuggestionModel.mentionedHandle(in: "meet @ 5") == nil)
        #expect(CardSuggestionModel.mentionedHandle(in: "hi @j") == nil)
    }

    @Test("The last handle typed wins, skipping any the sender dismissed")
    func lastUndismissedHandleWins() {
        let text = "@alice or @jeff"
        #expect(CardSuggestionModel.mentionedHandle(in: text)?.value == "jeff")
        #expect(CardSuggestionModel.mentionedHandle(in: text, skipping: [Username("jeff")!])?.value == "alice")
    }

    // MARK: - Lookup -

    @Test("A handle with an account behind it is offered as a card")
    func resolvedHandleIsSuggested() async {
        let source = Source()
        source.answers["jeff"] = Self.person()
        let model = Self.model(source)

        await Self.typed("You should talk to @jeff", into: model)

        #expect(model.suggestion?.username.value == "jeff")
        #expect(model.suggestion?.phase == .suggested)
    }

    @Test("An unclaimed handle offers nothing")
    func unclaimedHandleIsNotSuggested() async {
        let model = Self.model(Source())

        await Self.typed("talk to @nobody", into: model)

        #expect(model.suggestion == nil)
    }

    @Test("The person this chat is with is never offered")
    func counterpartIsNotSuggested() async {
        let source = Source()
        source.answers["jeff"] = Self.person()
        let model = Self.model(source, excluding: Self.jeffID)

        await Self.typed("hey @jeff", into: model)

        #expect(model.suggestion == nil)
    }

    @Test("Deleting the handle takes the offer back")
    func removingHandleClearsOffer() async {
        let source = Source()
        source.answers["jeff"] = Self.person()
        let model = Self.model(source)

        await Self.typed("talk to @jeff", into: model)
        await Self.typed("talk to ", into: model)

        #expect(model.suggestion == nil)
    }

    // MARK: - Taking and dismissing -

    @Test("Taking the offer attaches the card, and the card outlives the handle's text")
    func attachedCardSurvivesEdits() async {
        let source = Source()
        source.answers["jeff"] = Self.person()
        let model = Self.model(source)

        await Self.typed("talk to @jeff", into: model)
        model.accept()
        await Self.typed("talk to him", into: model)

        #expect(model.suggestion?.phase == .attached)
    }

    @Test("A dismissed handle is not offered again in the same draft")
    func dismissedHandleStaysDismissed() async {
        let source = Source()
        source.answers["jeff"] = Self.person()
        let model = Self.model(source)

        await Self.typed("talk to @jeff", into: model)
        model.dismiss()
        await Self.typed("talk to @jeff now", into: model)

        #expect(model.suggestion == nil)
    }

    @Test("Sending forgets what was dismissed")
    func resetForgetsDismissals() async {
        let source = Source()
        source.answers["jeff"] = Self.person()
        let model = Self.model(source)

        await Self.typed("talk to @jeff", into: model)
        model.dismiss()
        model.reset()
        await Self.typed("talk to @jeff", into: model)

        #expect(model.suggestion?.phase == .suggested)
    }

    // MARK: - What is sent -

    @Test("An attached card sends its link on a line after the words")
    func attachedLinkFollowsText() async {
        let source = Source()
        source.answers["jeff"] = Self.person()
        let model = Self.model(source)

        await Self.typed("talk to @jeff", into: model)
        model.accept()

        #expect(model.outgoing("talk to @jeff") == "talk to @jeff\nhttps://flipcash.com/jeff")
    }

    @Test("An attached card sends on its own when there are no words")
    func attachedLinkSendsAlone() async {
        let source = Source()
        source.answers["jeff"] = Self.person()
        let model = Self.model(source)

        await Self.typed("@jeff", into: model)
        model.accept()

        #expect(model.outgoing(nil) == "https://flipcash.com/jeff")
    }

    @Test("An offer nobody took sends the words unchanged")
    func untakenOfferSendsWordsOnly() async {
        let source = Source()
        source.answers["jeff"] = Self.person()
        let model = Self.model(source)

        await Self.typed("talk to @jeff", into: model)

        #expect(model.outgoing("talk to @jeff") == "talk to @jeff")
        #expect(model.outgoing(nil) == nil)
    }
}
