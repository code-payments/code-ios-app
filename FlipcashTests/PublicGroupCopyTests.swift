//
//  PublicGroupCopyTests.swift
//  FlipcashTests
//

import Foundation
import Testing
@testable import Flipcash
import FlipcashCore
import FlipcashStore

@MainActor
@Suite("Public group copy")
struct PublicGroupCopyTests {

    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func chatter(_ name: String, minutesAgo: Double?, isCreator: Bool = false) -> SampledChatter {
        SampledChatter(
            userID: UUID(),
            profile: Profile(displayName: name, phone: Phone?.none, email: nil),
            lastSentAt: minutesAgo.map { now.addingTimeInterval(-$0 * 60) },
            isCreator: isCreator
        )
    }

    // MARK: - Lines

    @Test("The summary names the count, singular for one, and drops it while unknown")
    func summary() {
        #expect(PublicGroupCopy.summary(memberCount: 22) == "Public group · 22 members")
        #expect(PublicGroupCopy.summary(memberCount: 1) == "Public group · 1 member")
        #expect(PublicGroupCopy.summary(memberCount: 0) == "Public group")
        #expect(PublicGroupCopy.summary(memberCount: nil) == "Public group")
    }

    @Test("The headline counts the week's chatters, and says quiet for none")
    func chatting() {
        #expect(PublicGroupCopy.chatting(count: 84) == "84 chatting this week")
        #expect(PublicGroupCopy.chatting(count: 1) == "1 chatting this week")
        #expect(PublicGroupCopy.chatting(count: 0) == "Quiet this week")
    }

    @Test("The last message's age steps through minutes, hours and days")
    func lastMessage() {
        func age(minutes: Double) -> String {
            PublicGroupCopy.lastMessage(at: now.addingTimeInterval(-minutes * 60), now: now)
        }
        #expect(age(minutes: 0.5) == "just now")
        #expect(age(minutes: 2) == "2m ago")
        #expect(age(minutes: 3 * 60) == "3h ago")
        #expect(age(minutes: 24 * 60) == "1 day ago")
        #expect(age(minutes: 12 * 24 * 60) == "12 days ago")
    }

    @Test("The meta line leaves out whichever part is unknown")
    func pulseMeta() {
        let twoMinutesAgo = now.addingTimeInterval(-120)
        #expect(PublicGroupCopy.pulseMeta(lastMessageAt: twoMinutesAgo, memberCount: 22, now: now) == "Last message 2m ago · 22 members")
        #expect(PublicGroupCopy.pulseMeta(lastMessageAt: nil, memberCount: 22, now: now) == "22 members")
        #expect(PublicGroupCopy.pulseMeta(lastMessageAt: twoMinutesAgo, memberCount: nil, now: now) == "Last message 2m ago")
        #expect(PublicGroupCopy.pulseMeta(lastMessageAt: nil, memberCount: 0, now: now) == nil)
    }

    // MARK: - Pulse

    @Test("Only chatters inside the seven-day window count, newest first")
    func pulseWindow() {
        let pulse = PublicGroupPulse(
            chatters: [
                chatter("Old", minutesAgo: 8 * 24 * 60),
                chatter("Quiet", minutesAgo: nil, isCreator: true),
                chatter("Recent", minutesAgo: 5),
                chatter("Newest", minutesAgo: 1),
            ],
            now: now
        )

        #expect(pulse.chattingCount == 2)
        #expect(pulse.faces.map(\.name) == ["Newest", "Recent"])
        #expect(pulse.overflow == 0)
        #expect(pulse.lastMessageAt == now.addingTimeInterval(-60))
    }

    @Test("The facepile caps at five and the rest are the overflow")
    func pulseOverflow() {
        let chatters = (1...8).map { chatter("Person \($0)", minutesAgo: Double($0)) }
        let pulse = PublicGroupPulse(chatters: chatters, now: now)

        #expect(pulse.chattingCount == 8)
        #expect(pulse.faces.count == PublicGroupPulse.faceLimit)
        #expect(pulse.overflow == 3)
    }

    @Test("A sample with nobody inside the window is quiet but still knows the last message")
    func pulseQuiet() {
        let pulse = PublicGroupPulse(chatters: [chatter("Ted", minutesAgo: 12 * 24 * 60, isCreator: true)], now: now)

        #expect(pulse.chattingCount == 0)
        #expect(pulse.faces.isEmpty)
        #expect(pulse.lastMessageAt != nil)
    }

    // MARK: - Requirement tiles

    private func requirements(join: Decimal?, chat: Decimal?) -> GroupBalanceRequirements? {
        GroupBalanceRequirements(ConversationRules(
            listener: join.map { [.minimumBalance(MinimumBalanceRequirement(amount: .usd($0)))] } ?? [],
            speaker: chat.map { [.minimumBalance(MinimumBalanceRequirement(amount: .usd($0)))] } ?? []
        ))
    }

    @Test("Equal join and chat rules collapse to one tile")
    func collapsedTile() throws {
        let rules = try #require(requirements(join: 100, chat: 100))

        let tiles = PublicGroupRequirementTile.tiles(for: rules, metadata: [:])

        #expect(tiles.map(\.purpose) == [.joinAndChat])
        #expect(tiles.first?.amount == "$100")
    }

    @Test("A join rule with no speaker rule is one tile too")
    func joinOnlyTile() throws {
        let rules = try #require(requirements(join: 50, chat: nil))

        #expect(PublicGroupRequirementTile.tiles(for: rules, metadata: [:]).map(\.purpose) == [.joinAndChat])
    }

    @Test("Different join and chat rules are two tiles")
    func splitTiles() throws {
        let rules = try #require(requirements(join: 50, chat: 100))

        let tiles = PublicGroupRequirementTile.tiles(for: rules, metadata: [:])

        #expect(tiles.map(\.purpose) == [.join, .chat])
        #expect(tiles.map(\.amount) == ["$50", "$100"])
    }
}
