//
//  CurrencyInfoViewModelTests.swift
//  FlipcashTests
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

/// Pins the loading-state churn behavior behind the Wallet → Currency Info
/// AppHang: redundant `loadingState` reassignments re-render the whole screen
/// (including the navigation-bar principal item) mid-transition.
@MainActor
@Suite("CurrencyInfoViewModel loading-state churn")
struct CurrencyInfoViewModelTests {

    private func makeViewModel(
        seeding metadata: MintMetadata
    ) throws -> (viewModel: CurrencyInfoViewModel, database: Database) {
        let database = Database.mock
        try database.insert(mints: [metadata], date: .now)

        let ratesController = RatesController(container: .mock, database: database)
        let session = Session.makeMock(database: database, ratesController: ratesController)

        let viewModel = CurrencyInfoViewModel(
            mint: metadata.address,
            session: session,
            database: database,
            ratesController: ratesController
        )
        return (viewModel, database)
    }

    /// Bounded window for the `Updateable` notification hop
    /// (`Task { @MainActor ... }`) to run when the expected outcome is that
    /// nothing happens — a negative can't be awaited, only outwaited.
    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(50))
    }

    @Test("Cached entry: loadMintMetadata does not invalidate loadingState")
    func loadMintMetadata_cachedUnchangedRow_doesNotInvalidate() async throws {
        let (viewModel, _) = try makeViewModel(seeding: .makeLaunchpad())
        #expect(viewModel.isLoaded)

        await confirmation("loadingState invalidated", expectedCount: 0) { invalidated in
            withObservationTracking {
                _ = viewModel.loadingState
            } onChange: {
                invalidated()
            }
            await viewModel.loadMintMetadata()
        }
    }

    @Test("A database change that leaves the row identical does not invalidate loadingState")
    func databaseChange_identicalRow_doesNotInvalidate() async throws {
        let metadata = MintMetadata.makeLaunchpad()
        let (viewModel, database) = try makeViewModel(seeding: metadata)
        await viewModel.loadMintMetadata()

        // A no-op poll: same content, later date. The write gate keeps the
        // stored row byte-identical, so the requery must compare equal.
        try database.insert(mints: [metadata], date: .now + 60)

        try await confirmation("loadingState invalidated", expectedCount: 0) { invalidated in
            withObservationTracking {
                _ = viewModel.loadingState
            } onChange: {
                invalidated()
            }
            NotificationCenter.default.post(name: .databaseDidChange, object: nil)
            try await settle()
        }
    }

    @Test("A real supply change still updates loadingState")
    func databaseChange_supplyChanged_updates() async throws {
        let metadata = MintMetadata.makeLaunchpad(supplyFromBonding: 100)
        let (viewModel, database) = try makeViewModel(seeding: metadata)
        await viewModel.loadMintMetadata()

        try database.updateLiveSupply(
            updates: [ReserveStateUpdate(mint: metadata.address, supplyFromBonding: 999)],
            date: .now
        )
        NotificationCenter.default.post(name: .databaseDidChange, object: nil)

        try await waitUntil(viewModel) { $0.mintMetadata?.supplyFromBonding == 999 }
    }
}
