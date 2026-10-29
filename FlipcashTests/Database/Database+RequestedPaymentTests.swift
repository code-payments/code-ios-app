//
//  Database+RequestedPaymentTests.swift
//  FlipcashTests
//

import Testing
import Foundation
import FlipcashCore
import FlipcashStore
@testable import Flipcash

@Suite("Database+RequestedPayment")
struct DatabaseRequestedPaymentTests {

    private static let payment = Activity.RequestedPayment(
        conversationID: ConversationID(data: Data((0..<16).map(UInt8.init))),
        paymentRequestID: PaymentRequestID(data: Data((16..<32).map(UInt8.init)))
    )

    private static func activity(payment: Activity.RequestedPayment?) -> Activity {
        Activity(
            id: .jeffy,
            state: .completed,
            kind: .gave,
            title: "Sent",
            exchangedFiat: .mockOne,
            date: .now,
            metadata: nil,
            requestedPayment: payment
        )
    }

    @Test("A payment for a request reads back with the same chat and request, per mint and recent")
    func roundTrip() throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }

        try database.insertActivities(activities: [Self.activity(payment: Self.payment)])

        #expect(try database.getRecentActivities(limit: 10).first?.requestedPayment == Self.payment)
        #expect(try database.getActivities(mint: ExchangedFiat.mockOne.mint).first?.requestedPayment == Self.payment)
    }

    @Test("A payment that paid no request reads back nil")
    func noRequest() throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }

        try database.insertActivities(activities: [Self.activity(payment: nil)])

        #expect(try database.getRecentActivities(limit: 10).first?.requestedPayment == nil)
    }

    @Test("Re-inserting an activity without its request removes the stored link")
    func resyncDropsLink() throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }

        try database.insertActivities(activities: [Self.activity(payment: Self.payment)])
        try database.insertActivities(activities: [Self.activity(payment: nil)])

        #expect(try database.getRecentActivities(limit: 10).first?.requestedPayment == nil)
    }
}
