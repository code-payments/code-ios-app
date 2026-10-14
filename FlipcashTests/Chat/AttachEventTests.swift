//
//  AttachEventTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
@testable import Flipcash

@MainActor
@Suite("Attach events")
struct AttachEventTests {

    private static let screen = CGRect(x: 0, y: 0, width: 402, height: 800)

    @Test(
        "Each event does the same thing in each host as the bar and overlay did before",
        arguments: [
            (AttachEvent.draftChanged, AttachHost.bar, AttachEventResponse.dismissPanel),
            (.draftChanged, .keyboardWindow, .dismissPanel),
            (.editBegan, .bar, .clearForEdit),
            (.editBegan, .inputView, .clearForEdit),
            (.fieldFocused, .bar, .dismissPanel),
            (.fieldFocused, .keyboardWindow, .none),
            (.fieldBlurred, .bar, .none),
            (.fieldBlurred, .keyboardWindow, .reset),
            (.fieldBlurred, .inputView, .reset),
            (.appBackgrounded, .bar, .none),
            (.appBackgrounded, .keyboardWindow, .reset),
            (.appBackgrounded, .inputView, .reset),
            (.keyboardWillHide, .bar, .none),
            (.keyboardWillHide, .keyboardWindow, .reset),
            (.keyboardWillHide, .inputView, .none),
            (.keyboardWindowLost, .keyboardWindow, .reset),
            (.keyboardWindowLost, .inputView, .reset),
        ]
    )
    func responseTable(event: AttachEvent, host: AttachHost, expected: AttachEventResponse) {
        #expect(event.response(in: host) == expected)
    }

    @Test("Typing dismisses an open panel")
    func draftDismissesPanel() {
        let model = ConversationBarModel()
        model.attachPanel.open()
        model.handle(.draftChanged, in: .bar)
        #expect(!model.attachPanel.isOpen)
    }

    @Test("Starting an edit closes an open card at once")
    func editClosesCard() {
        let model = ConversationBarModel()
        model.attachCard.open(.photos, screen: Self.screen)
        model.handle(.editBegan, in: .bar)
        #expect(!model.attachCard.isOpen)
    }

    @Test("Backgrounding leaves the bar's card up")
    func backgroundKeepsBarCard() {
        let model = ConversationBarModel()
        model.attachCard.open(.photos, screen: Self.screen)
        model.handle(.appBackgrounded, in: .bar)
        #expect(model.attachCard.isOpen)
    }

    @Test("Backgrounding takes the card over the keyboard down and reports a reset")
    func backgroundResetsOverlayCard() {
        let model = ConversationBarModel()
        model.attachCard.open(.photos, screen: Self.screen)
        let response = model.handle(.appBackgrounded, in: .keyboardWindow)
        #expect(response == .reset)
        #expect(!model.attachCard.isOpen)
    }

    @Test("The close line reports the host the surface was opened in")
    func closeReportsOpenedHost() {
        let model = ConversationBarModel()
        #expect(model.attachHost == .bar)
        model.attachDidOpen(in: .keyboardWindow, details: [:])
        #expect(model.attachHost == .keyboardWindow)
        model.attachDidOpen(in: .bar, details: [:])
        #expect(model.attachHost == .bar)
    }
}
