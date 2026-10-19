//
//  SystemNoticeStringsTests.swift
//  FlipcashCoreTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
@testable import FlipcashCore

@Suite("System notice wording")
struct SystemNoticeStringsTests {

    private let me = UUID()
    private let ada = UUID()
    private let bob = UUID()

    private func text(
        _ event: ConversationMessage.SystemEvent?,
        selfID: UUID? = nil,
        known: [UUID: String] = [:]
    ) -> String {
        SystemNoticeStrings.text(for: event, fallbackText: "fallback", selfID: selfID ?? me, nameOf: { known[$0] })
    }

    @Test("A direct join names the joiner")
    func directJoin() {
        #expect(text(.userJoined(userID: ada, admittedBy: nil), known: [ada: "Ada"]) == "Ada joined the group")
    }

    @Test("The viewer joining reads as You")
    func viewerJoined() {
        #expect(text(.userJoined(userID: me, admittedBy: nil)) == "You joined the group")
    }

    @Test("An admitted join names both users")
    func admitted() {
        #expect(text(.userJoined(userID: bob, admittedBy: ada), known: [ada: "Ada", bob: "Bob"]) == "Ada added Bob")
    }

    @Test("The viewer being admitted reads as added you")
    func viewerAdmitted() {
        #expect(text(.userJoined(userID: me, admittedBy: ada), known: [ada: "Ada"]) == "Ada added you")
    }

    @Test("The viewer admitting reads as You added")
    func viewerAdmitting() {
        #expect(text(.userJoined(userID: bob, admittedBy: me), known: [bob: "Bob"]) == "You added Bob")
    }

    @Test("An admitter who is the joiner is no admitter")
    func selfAdmit() {
        #expect(text(.userJoined(userID: ada, admittedBy: ada), known: [ada: "Ada"]) == "Ada joined the group")
        #expect(text(.userJoined(userID: me, admittedBy: me)) == "You joined the group")
    }

    @Test("Any name the sentence needs being unknown falls back")
    func unknownNames() {
        #expect(text(.userJoined(userID: ada, admittedBy: nil)) == "fallback")
        #expect(text(.userJoined(userID: bob, admittedBy: ada), known: [bob: "Bob"]) == "fallback")
        #expect(text(.userJoined(userID: bob, admittedBy: ada), known: [ada: "Ada"]) == "fallback")
        #expect(text(.userJoined(userID: bob, admittedBy: ada)) == "fallback")
        #expect(text(.userJoined(userID: me, admittedBy: ada)) == "fallback")
        #expect(text(.userJoined(userID: bob, admittedBy: me)) == "fallback")
    }

    @Test("A notice with no event shows its fallback text")
    func noEvent() {
        #expect(text(nil) == "fallback")
    }

    @Test("Nobody is the viewer when the viewer is unknown")
    func noSelf() {
        let result = SystemNoticeStrings.text(
            for: .userJoined(userID: me, admittedBy: nil), fallbackText: "fallback", selfID: nil, nameOf: { _ in "Me" }
        )
        #expect(result == "Me joined the group")
    }
}
