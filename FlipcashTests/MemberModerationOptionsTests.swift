//
//  MemberModerationOptionsTests.swift
//  FlipcashTests
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@Suite("Member moderation options")
struct MemberModerationOptionsTests {

    private func resolve(
        canSilence: Bool = true,
        canBan: Bool = true,
        isCreator: Bool = false,
        isSelf: Bool = false,
        isRestricted: Bool = false
    ) -> MemberModerationOptions {
        MemberModerationOptions.resolve(canSilence: canSilence, canBan: canBan, isCreator: isCreator, isSelf: isSelf, isRestricted: isRestricted)
    }

    @Test("A host with both flags gets Restrict and Remove on an unrestricted member, and no Report")
    func host_unrestricted() {
        let options = resolve()
        #expect(options.silence == .restrict)
        #expect(options.canRemove)
        #expect(options.hasGroupActions)
        #expect(!options.showsReport)
        #expect(!options.showsRestriction)
    }

    @Test("A restricted member offers Lift in place of Restrict and shows the restriction")
    func host_restricted() {
        let options = resolve(isRestricted: true)
        #expect(options.silence == .lift)
        #expect(options.canRemove)
        #expect(options.showsRestriction)
    }

    @Test("Each action needs its own permission flag")
    func flags() {
        let silenceOnly = resolve(canBan: false)
        #expect(silenceOnly.silence == .restrict)
        #expect(!silenceOnly.canRemove)

        let banOnly = resolve(canSilence: false)
        #expect(banOnly.silence == nil)
        #expect(banOnly.canRemove)
        #expect(!banOnly.showsReport)
    }

    @Test("A moderator who can only ban still sees a member's restriction")
    func banOnly_seesRestriction() {
        #expect(resolve(canSilence: false, isRestricted: true).showsRestriction)
    }

    @Test("A member with neither flag gets no group actions and gets Report")
    func member() {
        let options = resolve(canSilence: false, canBan: false, isRestricted: true)
        #expect(options.silence == nil)
        #expect(!options.canRemove)
        #expect(!options.hasGroupActions)
        #expect(options.showsReport)
        #expect(!options.showsRestriction)
    }

    @Test("The creator's entry has no group actions, so a host sees Report on it")
    func creator() {
        let options = resolve(isCreator: true)
        #expect(!options.hasGroupActions)
        #expect(options.showsReport)
        #expect(!options.showsRestriction)
    }

    @Test("The viewer's own entry has no group actions")
    func viewerSelf() {
        let options = resolve(isSelf: true)
        #expect(!options.hasGroupActions)
        #expect(!options.showsRestriction)
    }
}

@MainActor
@Suite("Restricted status copy")
struct RestrictedStatusCopyTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func left(_ seconds: TimeInterval) -> String {
        GroupModerationCopy.timeLeft(until: now.addingTimeInterval(seconds), now: now)
    }

    @Test("Time left reads in its two largest units, rounded down to the minute")
    func timeLeft() {
        #expect(left(3600 - 1) == "59m left")
        #expect(left(3600) == "1h left")
        #expect(left(6 * 3600 + 12 * 60 + 30) == "6h 12m left")
        #expect(left(7 * 86_400 - 60) == "6d 23h left")
        #expect(left(2 * 86_400) == "2d left")
    }

    @Test("Under a minute still reads as a minute")
    func underAMinute() {
        #expect(left(20) == "1m left")
    }

    @Test("A timed restriction reads its time left, and Forever reads plain Restricted")
    func status() {
        #expect(GroupModerationCopy.restrictedStatus(.until(now.addingTimeInterval(3599)), now: now) == "Restricted · 59m left")
        #expect(GroupModerationCopy.restrictedStatus(.forever, now: now) == "Restricted")
    }
}

@MainActor
@Suite("Group restrictions")
struct GroupRestrictionsTests {

    private let chat = ConversationID(data: Data(repeating: 1, count: 32))
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("A read holds silenced members and leaves out removed ones")
    func read() async {
        let silenced = UUID()
        let removed = UUID()
        let restrictions = GroupRestrictions { _ in
            [
                ConversationRestrictedUser(userID: silenced, displayName: "A", silence: .forever),
                ConversationRestrictedUser(userID: removed, displayName: "B", silence: .forever, bannedAt: Date(timeIntervalSince1970: 0)),
            ]
        }
        await restrictions.refresh(chat)
        #expect(restrictions.silence(of: silenced, in: chat, at: now) == .forever)
        #expect(restrictions.silence(of: removed, in: chat, at: now) == nil)
    }

    @Test("A lapsed timed silence reads as none")
    func lapsed() {
        let member = UUID()
        let restrictions = GroupRestrictions { _ in [] }
        restrictions.record(.until(now.addingTimeInterval(60)), for: member, in: chat)
        #expect(restrictions.silence(of: member, in: chat, at: now) != nil)
        #expect(restrictions.silence(of: member, in: chat, at: now.addingTimeInterval(61)) == nil)
    }

    @Test("A silence this device set or lifted wins over a trailing read")
    func localWriteWins() async {
        let lifted = UUID()
        let silenced = UUID()
        let restrictions = GroupRestrictions { _ in
            // The index still has the lift's target restricted and hasn't seen the new silence.
            [ConversationRestrictedUser(userID: lifted, displayName: "A", silence: .forever)]
        }
        restrictions.record(nil, for: lifted, in: chat)
        restrictions.record(.forever, for: silenced, in: chat)
        await restrictions.refresh(chat)
        #expect(restrictions.silence(of: lifted, in: chat, at: now) == nil)
        #expect(restrictions.silence(of: silenced, in: chat, at: now) == .forever)
    }

    @Test("A failed read keeps what was held")
    func failedRead() async {
        struct Failure: Error {}
        let member = UUID()
        var fails = false
        let restrictions = GroupRestrictions { _ in
            if fails { throw Failure() }
            return [ConversationRestrictedUser(userID: member, displayName: "A", silence: .forever)]
        }
        await restrictions.refresh(chat)
        fails = true
        await restrictions.refresh(chat)
        #expect(restrictions.silence(of: member, in: chat, at: now) == .forever)
    }
}
