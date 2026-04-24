//
//  Regression_69ea049e.swift
//  Flipcash
//
//  Hang: TransactionHistoryScreen.init synchronously ran
//        Database.getActivities on the main thread via a Updateable { ... }
//        wrapper. The destination closure in navigationDestinationCompat
//        re-evaluated on every parent body pass while the screen was
//        presented, so up to 1024 NSDateFormatter.dateFromString parses ran
//        on main each time — crossing the iOS 17/18 ANR watchdog.
//
//  Fix:  Added Database.getActivities(mint:) async that hops off main onto
//        a global dispatch queue. TransactionHistoryScreen's init no longer
//        touches the DB; the load runs from .task(id:).
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@Suite("Regression: 69ea049e – SQLite off main in TransactionHistoryScreen", .bug("69ea049e0174bec1b4390000"))
struct Regression_69ea049e {

    private static func makeActivity(id: PublicKey, title: String, date: Date) -> Activity {
        Activity(
            id: id,
            state: .completed,
            kind: .gave,
            title: title,
            exchangedFiat: .mockOne,
            date: date,
            metadata: nil
        )
    }

    @Test("async getActivities returns every persisted activity for the mint, off the main thread")
    func asyncReturnsPersistedActivities() async throws {
        let db = try Database.makeTemp()

        // Insert rows so the read path exercises row mapping +
        // NSDateFormatter parsing — the site of the ANR inside
        // `Row.get<Date>`. An empty-table test would miss that.
        // `ExchangedFiat.mockOne` is denominated in USDF, so `mint` on
        // each persisted row is `.usdf`.
        let now = Date.now
        try db.insertActivities(activities: [
            Self.makeActivity(id: .jeffy, title: "A", date: now),
            Self.makeActivity(id: .usdc, title: "B", date: now.addingTimeInterval(-1)),
        ])

        let loaded = try await db.getActivities(mint: .usdf)

        // Both rows persisted under mint=.usdf (per the mock's ExchangedFiat).
        #expect(loaded.count == 2)
    }
}
