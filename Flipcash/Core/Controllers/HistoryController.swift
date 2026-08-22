//
//  HistoryController.swift
//  Code
//
//  Created by Dima Bart on 2025-04-11.
//

import Foundation
import FlipcashCore

private let logger = Logger(label: "flipcash.history-controller")

/// Owns transaction history for the current session.
///
/// Only one transaction-history screen is on display at a time, so the
/// controller tracks a single "active" mint. Views call ``setActiveMint(_:)``
/// to declare which mint they're showing, then read from ``activities``; the
/// controller loads from the local DB and refreshes that slice after each
/// ``sync()``.
///
/// `sync()` is the single entry point for refreshing from the server: it
/// fetches new activities (delta + pending), writes them to the local DB,
/// then reloads the active slice so observers see the new state.
///
/// Inject via `@Environment(HistoryController.self)`.
@Observable
class HistoryController {

    enum LoadingState: Equatable {
        case loading
        case loaded([Activity])
    }

    /// Whether the local history has been reconciled with the server yet, for
    /// callers that must tell "nothing ever happened on this account" apart from
    /// "we haven't looked". A fresh login starts every read of the local cache at
    /// empty, so an established account looks brand new until the first sync
    /// lands. `unavailable` ends the wait when the server can't be reached —
    /// nothing further is coming, so callers act on what they have.
    enum SyncState: Equatable {
        case unknown
        case synced
        case unavailable
    }

    private(set) var loadingState: LoadingState = .loading
    private(set) var syncState: SyncState = .unknown

    @ObservationIgnored private let client: FlipClient
    @ObservationIgnored private let database: Database
    @ObservationIgnored private let owner: AccountCluster
    @ObservationIgnored private var activeMint: PublicKey?

    private var ownerKeyPair: KeyPair {
        owner.authority.keyPair
    }

    // MARK: - Init -

    init(container: Container, database: Database, owner: AccountCluster) {
        self.client   = container.flipClient
        self.database = database
        self.owner    = owner
    }

    // MARK: - Observe -

    /// Declare which mint's activities should be exposed via ``loadingState``.
    /// On a real change of mint, clears the slice and reloads from the local
    /// DB. Re-calls with the same mint are no-ops; ``sync()`` is the refresh
    /// path while a mint stays active.
    func setActiveMint(_ mint: PublicKey) async {
        guard activeMint != mint else { return }
        activeMint = mint
        loadingState = .loading
        await reload()
    }

    /// Re-read the active mint's activities from the local DB. Called by
    /// ``sync()`` after writing new server data and by ``setActiveMint(_:)``.
    func reload() async {
        guard let mint = activeMint else {
            loadingState = .loaded([])
            return
        }
        do {
            let loaded = try await database.getActivities(mint: mint)
            guard activeMint == mint else { return }
            loadingState = .loaded(loaded)
        } catch is CancellationError {
            return
        } catch {
            logger.error("Failed to reload activities", metadata: [
                "mint": "\(mint.base58)",
                "error": "\(error)",
            ])
            if activeMint == mint {
                loadingState = .loaded([])
            }
        }
    }

    // MARK: - Fetch -

    func sync() {
        Task {
            do {
                let didDelta = try await syncDeltaHistory()
                let didPending = try await syncPendingActivities()
                syncState = .synced
                if didDelta || didPending {
                    await reload()
                }
            } catch {
                logger.error("Sync failed", metadata: ["error": "\(error)"])
                // A failure after a good sync leaves the state alone: the local
                // history is still reconciled, just not freshly.
                if syncState == .unknown {
                    syncState = .unavailable
                }
            }
        }
    }

    func syncPendingActivities() async throws -> Bool {
        let pendingIDs = try database.getPendingActivityIDs()
        guard !pendingIDs.isEmpty else {
            logger.debug("No pending activities")
            return false
        }
        let activities = try await client.fetchTransactionHistoryItemsByID(owner: ownerKeyPair, ids: pendingIDs)
        try database.transaction {
            try $0.insertActivities(activities: activities)
        }
        logger.info("Inserted pending activities", metadata: ["count": "\(activities.count)"])
        return true
    }

    /// Syncs everything newer than the latest locally-stored activity.
    ///
    /// The stored cursor is a server notification id, and the server can drop
    /// the notification it names — a history migration does exactly that. It
    /// then fails the request rather than ignoring the dead token, which would
    /// wedge every later sync on the same cursor, so a server-side failure
    /// falls back to a full resync.
    private func syncDeltaHistory() async throws -> Bool {
        guard let latestID = try database.getLatestActivityID() else {
            return try await syncHistory()
        }
        do {
            return try await syncHistory(since: latestID)
        } catch let error as ErrorFetchTransactionHistory where error.warrantsFullResync {
            logger.warning("Delta sync failed, resyncing full history", metadata: [
                "cursor": "\(latestID.base58)",
                "error": "\(error)",
            ])
            return try await syncHistory()
        }
    }

    private func syncHistory(since id: PublicKey? = nil) async throws -> Bool {
        let pageSize = 1024
        var cursor: PublicKey? = id

        var container: [Activity] = []

        var hasMore = true
        while hasMore {
            let activities = try await client.fetchTransactionHistory(
                owner: ownerKeyPair,
                pageSize: pageSize,
                since: cursor
            )

            if !activities.isEmpty {
                container.append(contentsOf: activities)
                cursor = activities.last?.id
            }

            hasMore = activities.count == pageSize
        }

        guard !container.isEmpty else {
            logger.info("No new activities")
            return false
        }
        try database.transaction {
            try $0.insertActivities(activities: container)
        }
        logger.info("Inserted activities", metadata: ["count": "\(container.count)"])
        return true
    }
}

