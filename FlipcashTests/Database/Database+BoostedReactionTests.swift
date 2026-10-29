//
//  Database+BoostedReactionTests.swift
//  FlipcashTests
//

import Testing
import Foundation
import FlipcashCore
import FlipcashStore
@testable import Flipcash

@Suite("Database+BoostedReaction")
struct DatabaseBoostedReactionTests {

    private static let boost = Activity.BoostedReaction(
        conversationID: ConversationID(data: Data((0..<16).map(UInt8.init))),
        messageID: MessageID(value: 42),
        emoji: "👍🏽"
    )

    private static func activity(boost: Activity.BoostedReaction?) -> Activity {
        Activity(
            id: .jeffy,
            state: .completed,
            kind: .gave,
            title: "Sent",
            exchangedFiat: .mockOne,
            date: .now,
            metadata: nil,
            boostedReaction: boost
        )
    }

    @Test("P1: a boosted payment reads back with the same chat, message and emoji")
    func roundTrip() throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }

        try database.insertActivities(activities: [Self.activity(boost: Self.boost)])

        let recent = try database.getRecentActivities(limit: 10)
        #expect(recent.first?.boostedReaction == Self.boost)

        let perMint = try database.getActivities(mint: ExchangedFiat.mockOne.mint)
        #expect(perMint.first?.boostedReaction == Self.boost)
    }

    @Test("P2: a payment without a boost reads back nil")
    func noBoost() throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }

        try database.insertActivities(activities: [Self.activity(boost: nil)])

        #expect(try database.getRecentActivities(limit: 10).first?.boostedReaction == nil)
    }

    @Test("Re-inserting an activity without its boost removes the stored boost")
    func resyncDropsBoost() throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }

        try database.insertActivities(activities: [Self.activity(boost: Self.boost)])
        try database.insertActivities(activities: [Self.activity(boost: nil)])

        #expect(try database.getRecentActivities(limit: 10).first?.boostedReaction == nil)
    }
}
