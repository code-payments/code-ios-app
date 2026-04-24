//
//  Mocks.swift
//  FlipcashTests
//
//  Test-only mocks for production types. These live in the test target so
//  production code stays free of test scaffolding. Types whose `.mock`
//  property is referenced by a `#Preview` in the app (e.g. `Container.mock`,
//  `SessionAuthenticator.mock`) must keep that property in production and
//  are not declared here.
//

import Foundation
@testable import Flipcash
import FlipcashCore

extension Database {
    /// Fresh, per-access SQLite file. Each read of `.mock` returns a new
    /// `Database` backed by a unique temp path, so tests never share state
    /// through a long-lived singleton file. Bind to a local if a single
    /// instance needs to be shared across multiple child constructions.
    static var mock: Database {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mock-\(UUID().uuidString).sqlite")
        return try! Database(url: url)
    }
}

extension HistoryController {
    static var mock: HistoryController {
        HistoryController(container: .mock, database: .mock, owner: .mock)
    }
}

extension RatesController {
    /// Fresh per access. Each `.mock` returns a new `RatesController` with a
    /// new underlying `Database`; bind to a local if the same instance is
    /// needed across multiple calls.
    static var mock: RatesController {
        RatesController(container: .mock, database: .mock)
    }
}

extension Session {
    /// Computed so each access builds a fresh object graph sharing ONE
    /// Database across the session, rates controller, and history controller
    /// (rather than each child pulling its own `.mock` and ending up with
    /// three inconsistent databases).
    static var mock: Session {
        makeMock(database: .mock)
    }

    /// Shared by `Session.mock`, `Session.unverifiedMock`, and the
    /// `SessionContainer.mock` inner Session — they all need the same shape
    /// but let the caller override `historyController`/`ratesController` so
    /// the container can expose the same instances it handed the Session.
    static func makeMock(
        database: Database,
        historyController: HistoryController? = nil,
        ratesController: RatesController? = nil
    ) -> Session {
        Session(
            container: .mock,
            historyController: historyController ?? HistoryController(container: .mock, database: database, owner: .mock),
            ratesController: ratesController ?? RatesController(container: .mock, database: database),
            database: database,
            keyAccount: .mock,
            owner: .init(
                authority: .derive(using: .primary(), mnemonic: .mock),
                mint: .mock,
                timeAuthority: .usdcAuthority
            ),
            userID: UUID()
        )
    }
}

extension SessionContainer {
    /// Computed so each access builds a fresh graph sharing ONE Database
    /// across session / ratesController / historyController, matching what
    /// production wires up. `static let` would have each `.mock` evaluate
    /// its own Database at init and diverge.
    @MainActor
    static var mock: SessionContainer {
        let database = Database.mock
        let ratesController = RatesController(container: .mock, database: database)
        let historyController = HistoryController(container: .mock, database: database, owner: .mock)
        let session = Session.makeMock(
            database: database,
            historyController: historyController,
            ratesController: ratesController
        )
        return .init(
            session: session,
            database: database,
            walletConnection: .mock,
            ratesController: ratesController,
            historyController: historyController,
            pushController: .mock,
            flipClient: Container.mock.flipClient
        )
    }
}
