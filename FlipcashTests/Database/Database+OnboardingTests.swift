//
//  Database+OnboardingTests.swift
//  FlipcashTests
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@Suite(.serialized)
struct DatabaseOnboardingTests {

    // MARK: - Helpers

    private static func makeActivity(
        index: Int = 0,
        kind: Activity.Kind,
        state: Activity.State = .completed
    ) -> Activity {
        Activity(
            id: .testMint(index: index),
            state: state,
            kind: kind,
            title: "Activity",
            exchangedFiat: .mockOne,
            date: .now,
            metadata: nil
        )
    }

    // MARK: - hasEverAddedMoney

    @Test(
        "hasEverAddedMoney is true for every completed incoming-money kind",
        arguments: [Activity.Kind.bought, .deposited, .received, .distributed]
    )
    func hasEverAddedMoney_incomingKinds(kind: Activity.Kind) throws {
        let (db, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }

        #expect(try db.hasEverAddedMoney() == false)

        try db.insertActivities(activities: [Self.makeActivity(kind: kind)])

        #expect(try db.hasEverAddedMoney() == true)
    }

    @Test(
        "hasEverAddedMoney ignores outgoing and same-wallet kinds",
        arguments: [Activity.Kind.gave, .withdrew, .cashLink, .paid, .sold, .swapped]
    )
    func hasEverAddedMoney_nonIncomingKinds(kind: Activity.Kind) throws {
        let (db, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }

        try db.insertActivities(activities: [Self.makeActivity(kind: kind)])

        #expect(try db.hasEverAddedMoney() == false)
    }

    @Test("hasEverAddedMoney ignores a pending deposit until it completes")
    func hasEverAddedMoney_pendingDoesNotCount() throws {
        let (db, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }

        try db.insertActivities(activities: [
            Self.makeActivity(kind: .deposited, state: .pending),
        ])
        #expect(try db.hasEverAddedMoney() == false)

        // Same id, now settled — the upsert flips the stored state.
        try db.insertActivities(activities: [
            Self.makeActivity(kind: .deposited, state: .completed),
        ])
        #expect(try db.hasEverAddedMoney() == true)
    }

    @Test("hasEverAddedMoney sees a tip received alongside outgoing history")
    func hasEverAddedMoney_tipAmongOutgoing() throws {
        let (db, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }

        try db.insertActivities(activities: [
            Self.makeActivity(index: 1, kind: .gave),
            Self.makeActivity(index: 2, kind: .withdrew),
            Self.makeActivity(index: 3, kind: .received),
        ])

        #expect(try db.hasEverAddedMoney() == true)
    }
}
