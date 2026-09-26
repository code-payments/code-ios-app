//
//  InvitePeopleViewModelTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("Invite People sheet")
struct InvitePeopleViewModelTests {

    private let url = URL(string: "https://app.flipcash.com/g/abc")!
    private let a = ConversationID(data: Data(repeating: 1, count: 32))
    private let b = ConversationID(data: Data(repeating: 2, count: 32))
    private let c = ConversationID(data: Data(repeating: 3, count: 32))

    /// Records every send in order; answers false for any text sent to a chat in `failing`.
    @MainActor
    private final class Recorder {
        var sent: [(text: String, chatID: ConversationID)] = []
        var failing: Set<ConversationID> = []

        func send(_ text: String, _ chatID: ConversationID) async -> Bool {
            sent.append((text, chatID))
            return !failing.contains(chatID)
        }
    }

    // MARK: - Composer

    @Test("The message bar is hidden with nothing picked")
    func composer_hiddenWithNoSelection() {
        let model = InvitePeopleViewModel(url: url)
        #expect(model.showsComposer == false)
    }

    @Test("The message bar shows once one chat is picked, and hides again when it's unpicked")
    func composer_followsSelection() {
        let model = InvitePeopleViewModel(url: url)
        model.toggleSelection(a)
        #expect(model.showsComposer)
        #expect(model.isSelected(a))

        model.toggleSelection(a)
        #expect(model.showsComposer == false)
        #expect(model.isSelected(a) == false)
    }

    // MARK: - Send

    @Test("Each picked chat gets the link, then the message")
    func send_linkThenMessagePerChat() async {
        let model = InvitePeopleViewModel(url: url)
        let recorder = Recorder()
        model.toggleSelection(a)
        model.toggleSelection(b)
        model.message = "  join us  "

        _ = await model.sendInvites(via: recorder.send)

        #expect(recorder.sent.map(\.text) == [url.absoluteString, "join us", url.absoluteString, "join us"])
        #expect(recorder.sent.map(\.chatID) == [a, a, b, b])
    }

    @Test("A blank message sends only the link", arguments: ["", "   ", "\n\t"])
    func send_blankMessageSendsLinkOnly(message: String) async {
        let model = InvitePeopleViewModel(url: url)
        let recorder = Recorder()
        model.toggleSelection(a)
        model.message = message

        _ = await model.sendInvites(via: recorder.send)

        #expect(recorder.sent.map(\.text) == [url.absoluteString])
        #expect(recorder.sent.map(\.chatID) == [a])
    }

    @Test("It lands on the chat picked first, in tap order rather than list order")
    func send_returnsFirstPicked() async {
        let model = InvitePeopleViewModel(url: url)
        let recorder = Recorder()
        model.toggleSelection(c)
        model.toggleSelection(a)
        model.toggleSelection(b)

        let destination = await model.sendInvites(via: recorder.send)

        #expect(destination == c)
        #expect(recorder.sent.map(\.chatID) == [c, a, b])
    }

    @Test("Unpicking the first chat moves the landing to the next one picked")
    func send_unpickedFirstIsSkipped() async {
        let model = InvitePeopleViewModel(url: url)
        model.toggleSelection(a)
        model.toggleSelection(b)
        model.toggleSelection(a)

        let destination = await model.sendInvites(via: Recorder().send)

        #expect(destination == b)
    }

    @Test("One chat failing doesn't stop the rest, and its message isn't sent ahead of a missing link")
    func send_failureIsIsolated() async {
        let model = InvitePeopleViewModel(url: url)
        let recorder = Recorder()
        recorder.failing = [b]
        model.toggleSelection(a)
        model.toggleSelection(b)
        model.toggleSelection(c)
        model.message = "hi"

        let destination = await model.sendInvites(via: recorder.send)

        #expect(recorder.sent.map(\.chatID) == [a, a, b, c, c])
        #expect(recorder.sent.map(\.text) == [url.absoluteString, "hi", url.absoluteString, url.absoluteString, "hi"])
        #expect(destination == a)
        #expect(model.isSending == false)
    }

    @Test("Sending with nothing picked sends nothing and lands nowhere")
    func send_emptySelection() async {
        let model = InvitePeopleViewModel(url: url)
        let recorder = Recorder()

        let destination = await model.sendInvites(via: recorder.send)

        #expect(destination == nil)
        #expect(recorder.sent.isEmpty)
    }
}
