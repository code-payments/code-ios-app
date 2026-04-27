//
//  HistoryControllerTests.swift
//  FlipcashTests
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@MainActor
struct HistoryControllerTests {

    // MARK: - Helpers

    private static func makeCashLinkActivity(
        id: PublicKey = .jeffy,
        state: Activity.State,
        canCancel: Bool,
        title: String,
    ) -> Activity {
        Activity(
            id: id,
            state: state,
            kind: .cashLink,
            title: title,
            exchangedFiat: .mockOne,
            date: .now,
            metadata: .cashLink(
                Activity.CashLinkMetadata(vault: .usdc, canCancel: canCancel)
            )
        )
    }

    private static func makeController(database: Database) -> HistoryController {
        HistoryController(container: .mock, database: database, owner: .mock)
    }

    /// Unwrap the controller's loaded slice. Avoids full `Activity` equality —
    /// `Date` doesn't round-trip through SQLite with full nanosecond precision.
    private static func loadedActivities(_ controller: HistoryController) throws -> [Activity] {
        guard case .loaded(let activities) = controller.loadingState else {
            Issue.record("Expected .loaded state, got \(controller.loadingState)")
            throw TestFailure.notLoaded
        }
        return activities
    }

    private enum TestFailure: Error { case notLoaded }

    // MARK: - Initial state

    @Test("Initial loadingState is .loading before any mint is active")
    func initialStateIsLoading() throws {
        let controller = Self.makeController(database: try Database.makeTemp())
        #expect(controller.loadingState == .loading)
    }

    // MARK: - setActiveMint

    @Test("setActiveMint loads the mint's activities from the local DB")
    func setActiveMintLoadsActivities() async throws {
        let db = try Database.makeTemp()
        let pending = Self.makeCashLinkActivity(
            state: .pending, canCancel: true, title: "Sending $1.00",
        )
        try db.insertActivities(activities: [pending])

        let controller = Self.makeController(database: db)
        await controller.setActiveMint(.usdf)

        let activities = try Self.loadedActivities(controller)
        #expect(activities.count == 1)
        #expect(activities[0].id == .jeffy)
        #expect(activities[0].state == .pending)
        #expect(activities[0].cancellableCashLinkMetadata != nil)
    }

    @Test("setActiveMint with the same mint is a no-op — sync() is the refresh path")
    func setActiveMintSameMintDoesNotReload() async throws {
        let db = try Database.makeTemp()
        let pending = Self.makeCashLinkActivity(
            state: .pending, canCancel: true, title: "Sending $1.00",
        )
        try db.insertActivities(activities: [pending])

        let controller = Self.makeController(database: db)
        await controller.setActiveMint(.usdf)
        try #require(Self.loadedActivities(controller).first?.state == .pending)

        // Mutate the DB directly. The controller's slice must NOT pick this
        // up from a same-mint setActiveMint call — that's the re-mount-as-no-op
        // contract that prevents redundant DB reads.
        let completed = Self.makeCashLinkActivity(
            state: .completed, canCancel: false, title: "Cancelled $1.00",
        )
        try db.insertActivities(activities: [completed])

        await controller.setActiveMint(.usdf)

        let activities = try Self.loadedActivities(controller)
        #expect(activities.first?.state == .pending)
    }

    @Test("setActiveMint with a different mint switches the slice")
    func setActiveMintSwitchesSlice() async throws {
        let db = try Database.makeTemp()
        let usdfActivity = Self.makeCashLinkActivity(
            state: .pending, canCancel: true, title: "Sending $1.00",
        )
        try db.insertActivities(activities: [usdfActivity])

        let controller = Self.makeController(database: db)
        await controller.setActiveMint(.usdf)
        try #require(Self.loadedActivities(controller).count == 1)

        // Switch to a mint with no activities.
        await controller.setActiveMint(.usdc)

        let activities = try Self.loadedActivities(controller)
        #expect(activities.isEmpty)
    }

    // MARK: - reload

    @Test("reload picks up DB writes for the active mint — the post-sync refresh path")
    func reloadReflectsDBWrite() async throws {
        let db = try Database.makeTemp()
        let pending = Self.makeCashLinkActivity(
            state: .pending, canCancel: true, title: "Sending $1.00",
        )
        try db.insertActivities(activities: [pending])

        let controller = Self.makeController(database: db)
        await controller.setActiveMint(.usdf)

        // What HistoryController.sync() writes after the backend confirms a
        // cancel — same id, terminal state, no longer cancellable.
        let completed = Self.makeCashLinkActivity(
            state: .completed, canCancel: false, title: "Cancelled $1.00",
        )
        try db.insertActivities(activities: [completed])

        await controller.reload()

        let activities = try Self.loadedActivities(controller)
        #expect(activities.count == 1)
        #expect(activities[0].state == .completed)
        #expect(activities[0].cancellableCashLinkMetadata == nil)
        #expect(activities[0].title == "Cancelled $1.00")
    }
}
