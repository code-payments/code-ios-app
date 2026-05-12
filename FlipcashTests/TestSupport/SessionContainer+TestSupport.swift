//
//  SessionContainer+TestSupport.swift
//  FlipcashTests
//
//  Created by Raul Riera on 2026-04-22.
//

import Foundation
import FlipcashCore
@testable import Flipcash

extension SessionContainer {

    struct Holding {
        let mint: MintMetadata
        let quarks: UInt64
    }

    /// Builds a `SessionContainer` backed by an isolated on-disk SQLite
    /// database pre-populated with the given holdings via the real
    /// `Database.insert(mints:date:)` and `Database.insertBalance(...)`
    /// APIs. `Session.init` reads those balances through `Updateable`
    /// at construction, so the returned container's `session.balances`
    /// reflects the seed on the first access.
    ///
    /// Pass `limits` to also seed `session.limits` — useful for view
    /// models that gate on `sendLimitFor(currency:)` (the limits
    /// Updateable also loads at Session init, so this must run before
    /// the Session is constructed).
    ///
    /// Each call produces an independent database file so tests don't
    /// share balance state.
    @MainActor
    static func makeTest(holdings: [Holding], limits: Limits? = nil) throws -> SessionContainer {
        let database = try Database(
            url: URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("give-test-\(UUID().uuidString).sqlite")
        )

        let now = Date.now
        try database.insert(mints: holdings.map { $0.mint }, date: now)
        try database.transaction { db in
            for holding in holdings {
                try db.insertBalance(
                    quarks: holding.quarks,
                    mint: holding.mint.address,
                    costBasis: 0,
                    date: now
                )
            }
        }

        if let limits {
            try database.insertLimits(limits)
        }

        let ratesController = RatesController(container: .mock, database: database)
        let session = Session(
            container: .mock,
            historyController: .mock,
            ratesController: ratesController,
            database: database,
            keyAccount: .mock,
            owner: .init(
                authority: .derive(using: .primary(), mnemonic: .mock),
                mint: .mock,
                timeAuthority: .usdcAuthority
            ),
            userID: UUID()
        )

        return SessionContainer(
            session: session,
            database: database,
            walletConnection: .mock,
            ratesController: ratesController,
            historyController: .mock,
            pushController: .mock,
            flipClient: Container.mock.flipClient
        )
    }
}
