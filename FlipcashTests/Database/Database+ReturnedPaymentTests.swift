//
//  Database+ReturnedPaymentTests.swift
//  FlipcashTests
//

import Testing
import Foundation
import FlipcashCore
import FlipcashStore
@testable import Flipcash

@Suite("Database+ReturnedPayment")
struct DatabaseReturnedPaymentTests {

    private static let payment = Activity.ReturnedPayment(
        conversationID: ConversationID(data: Data((0..<16).map(UInt8.init))),
        messageID: MessageID(value: 42)
    )

    private static func activity(payment: Activity.ReturnedPayment?) -> Activity {
        Activity(
            id: .jeffy,
            state: .completed,
            kind: .gave,
            title: "Sent",
            exchangedFiat: .mockOne,
            date: .now,
            metadata: nil,
            returnedPayment: payment
        )
    }

    @Test("A return reads back with the same DM and message, per mint and recent")
    func roundTrip() throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }

        try database.insertActivities(activities: [Self.activity(payment: Self.payment)])

        #expect(try database.getRecentActivities(limit: 10).first?.returnedPayment == Self.payment)
        #expect(try database.getActivities(mint: ExchangedFiat.mockOne.mint).first?.returnedPayment == Self.payment)
    }

    @Test("Re-inserting an activity without its return removes the stored link")
    func resyncDropsLink() throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }

        try database.insertActivities(activities: [Self.activity(payment: Self.payment)])
        try database.insertActivities(activities: [Self.activity(payment: nil)])

        #expect(try database.getRecentActivities(limit: 10).first?.returnedPayment == nil)
    }
}
