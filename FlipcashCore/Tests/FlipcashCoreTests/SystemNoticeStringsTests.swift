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

    @Test("An invite join names whose invite link it was")
    func invitedJoin() {
        let known = [ada: "Ada", bob: "Bob"]
        #expect(text(.userJoinedViaInvite(userID: ada, invitedBy: bob), known: known) == "Ada joined with Bob’s invite link")
        #expect(text(.userJoinedViaInvite(userID: me, invitedBy: bob), known: known) == "You joined with Bob’s invite link")
        #expect(text(.userJoinedViaInvite(userID: ada, invitedBy: me), known: known) == "Ada joined with your invite link")
        #expect(text(.userJoinedViaInvite(userID: ada, invitedBy: bob), known: [ada: "Ada"]) == "fallback")
        #expect(text(.userJoinedViaInvite(userID: ada, invitedBy: me)) == "fallback")
    }

    @Test("Only the inviter's name in an invite join opens a profile")
    func inviterLink() {
        func link(_ event: ConversationMessage.SystemEvent, known: [UUID: String]) -> SystemNoticeUserLink? {
            let nameOf: (UUID) -> String? = { known[$0] }
            let text = SystemNoticeStrings.text(for: event, fallbackText: "fallback", selfID: me, nameOf: nameOf)
            return SystemNoticeStrings.userLink(for: event, text: text, selfID: me, nameOf: nameOf)
        }
        // The joiner's name contains the inviter's; the link is still the inviter's.
        let other = link(.userJoinedViaInvite(userID: ada, invitedBy: bob), known: [ada: "Bob Jr", bob: "Bob"])
        #expect(other == SystemNoticeUserLink(range: NSRange(location: 19, length: 3), userID: bob))
        let mine = link(.userJoinedViaInvite(userID: me, invitedBy: bob), known: [bob: "Bob"])
        #expect(mine == SystemNoticeUserLink(range: NSRange(location: 16, length: 3), userID: bob))
        #expect(link(.userJoinedViaInvite(userID: ada, invitedBy: me), known: [ada: "Ada"]) == nil)
        #expect(link(.userJoined(userID: ada, admittedBy: bob), known: [ada: "Ada", bob: "Bob"]) == nil)
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
