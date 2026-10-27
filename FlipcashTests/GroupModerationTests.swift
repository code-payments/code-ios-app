//
//  GroupModerationTests.swift
//  FlipcashTests
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("Group moderation")
struct GroupModerationTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func user(silence: ConversationSilenceState? = nil, bannedAt: Date? = nil) -> ConversationRestrictedUser {
        ConversationRestrictedUser(userID: UUID(), displayName: "Grampa", silence: silence, bannedAt: bannedAt)
    }

    @Test("A silenced user is listed under Silenced only")
    func silenced_onlySilenced() {
        let u = user(silence: .forever)
        #expect(u.belongs(on: .silenced, at: now))
        #expect(!u.belongs(on: .removed, at: now))
    }

    @Test("A user who is both banned and silenced appears only under Removed, marked also silenced")
    func both_onlyRemoved() {
        let u = user(silence: .forever, bannedAt: now)
        #expect(!u.belongs(on: .silenced, at: now))
        #expect(u.belongs(on: .removed, at: now))
        #expect(u.detail(on: .removed, now: now).hasSuffix(" · also silenced"))
    }

    @Test("A lapsed timed silence drops off the Silenced list")
    func lapsed_dropsOff() {
        let u = user(silence: .until(now.addingTimeInterval(-1)))
        #expect(!u.belongs(on: .silenced, at: now))
    }

    @Test("Row details read forever and removed")
    func details() {
        #expect(user(silence: .forever).detail(on: .silenced, now: now) == "Silenced · forever")
        #expect(user(bannedAt: now).detail(on: .removed, now: now).hasPrefix("Removed "))
        #expect(!user(bannedAt: now).detail(on: .removed, now: now).contains("also silenced"))
    }

    @Test("Silence durations resolve to an end instant or forever")
    func durations() {
        #expect(SilenceDuration.oneHour.silence(from: now) == .until(now.addingTimeInterval(3600)))
        #expect(SilenceDuration.oneWeek.silence(from: now) == .until(now.addingTimeInterval(7 * 86_400)))
        #expect(SilenceDuration.forever.silence(from: now) == .forever)
        #expect(SilenceDuration.allCases.map(\.title) == ["1 Hour", "8 Hours", "1 Week", "Forever"])
    }

    @Test("A silenced viewer's open composer becomes the silence pill until it lapses")
    func gate_override() {
        let silence = ConversationSilenceState.until(now.addingTimeInterval(60))
        #expect(ConversationGatePresentation.open.silenced(by: silence, at: now) == .readOnly(.silenced(silence)))
        #expect(ConversationGatePresentation.open.silenced(by: silence, at: now.addingTimeInterval(61)) == .open)
        #expect(ConversationGatePresentation.open.silenced(by: nil, at: now) == .open)
    }

    @Test("The pill sentence names the end time, or says forever")
    func sentence() {
        #expect(ConversationGatePanel.silencedSentence(.forever, now: now) == "You're silenced in this group")
        #expect(ConversationGatePanel.silencedSentence(.until(now.addingTimeInterval(3600)), now: now).hasPrefix("You're silenced until "))
    }

    @Test("Prompts use the member's first name and the group's name")
    func copy() {
        #expect(GroupModerationCopy.firstName(of: "Grampa Joe") == "Grampa")
        #expect(GroupModerationCopy.removeTitle(firstName: "Grampa") == "Remove Grampa?")
        #expect(GroupModerationCopy.bannedSubtitle(groupName: "Jeffy") == "The host removed you from Jeffy")
    }

    @Test("Toast copy names the member and the duration")
    func toastCopy() {
        #expect(GroupModerationCopy.silencedToast(firstName: "McAnsh", duration: .oneHour) == "McAnsh is silenced for 1 hour")
        #expect(GroupModerationCopy.silencedToast(firstName: "McAnsh", duration: .eightHours) == "McAnsh is silenced for 8 hours")
        #expect(GroupModerationCopy.silencedToast(firstName: "McAnsh", duration: .oneWeek) == "McAnsh is silenced for 1 week")
        #expect(GroupModerationCopy.silencedToast(firstName: "McAnsh", duration: .forever) == "McAnsh is silenced")
        #expect(GroupModerationCopy.unsilencedToast(firstName: "McAnsh") == "McAnsh can send messages again")
    }

    @Test("A silence change announces only after the server call succeeds")
    func toastOnlyOnSuccess() async throws {
        let server = FakeModeration()
        var announced: [String] = []
        let moderation = GroupModeration(
            moderation: server,
            owner: .mock,
            conversationID: ConversationID(data: Data(repeating: 1, count: 32)),
            announce: { announced.append($0) }
        )

        try await moderation.silence(UUID(), firstName: "McAnsh", duration: .oneWeek)
        try await moderation.unsilence(UUID(), firstName: "McAnsh")
        #expect(announced == ["McAnsh is silenced for 1 week", "McAnsh can send messages again"])

        server.fails = true
        await #expect(throws: (any Error).self) { try await moderation.silence(UUID(), firstName: "McAnsh", duration: .forever) }
        await #expect(throws: (any Error).self) { try await moderation.unsilence(UUID(), firstName: "McAnsh") }
        #expect(announced.count == 2)
    }
}

private final class FakeModeration: ConversationModeration, @unchecked Sendable {
    struct Failure: Error {}
    var fails = false

    func silenceUser(owner: KeyPair, conversationID: ConversationID, userID: UserID, silence: ConversationSilenceState) async throws { try check() }
    func unsilenceUser(owner: KeyPair, conversationID: ConversationID, userID: UserID) async throws { try check() }
    func banUser(owner: KeyPair, conversationID: ConversationID, userID: UserID) async throws { try check() }
    func unbanUser(owner: KeyPair, conversationID: ConversationID, userID: UserID) async throws { try check() }
    func getRestrictedUsers(owner: KeyPair, conversationID: ConversationID) async throws -> [ConversationRestrictedUser] { try check(); return [] }

    private func check() throws { if fails { throw Failure() } }
}
