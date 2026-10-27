//
//  AddMoneyRowStateTests.swift
//  FlipcashTests
//

import Foundation
import Testing
@testable import Flipcash

/// The wallet must not mistake a cold local cache for a brand-new account: on
/// every fresh login — switching accounts included — the history reads empty
/// until the first sync lands, and drawing that verdict greets an established
/// user with the Add Money row.
@Suite
@MainActor
struct AddMoneyRowStateTests {

    private static func state(
        addedMoney: Bool = false,
        sync: HistoryController.SyncState = .synced,
        storedActivity: Bool = false
    ) -> AddMoneyRowState {
        AddMoneyRowState(
            hasAddedMoney: addedMoney,
            historySyncState: sync,
            hasStoredActivity: storedActivity
        )
    }

    @Test("The row shows once history has synced and no money was ever added")
    func shownAfterSync() {
        let state = Self.state(sync: .synced)
        #expect(!state.isAwaitingHistory)
        #expect(state.isVisible)
    }

    @Test("The row is hidden once money has been added")
    func hiddenAfterMoneyAdded() {
        #expect(!Self.state(addedMoney: true, sync: .synced).isVisible)
        #expect(!Self.state(addedMoney: true, sync: .unknown).isVisible)
    }

    @Test("The row is withheld while history is unsynced and nothing is stored")
    func withheldBeforeFirstSync() {
        let state = Self.state(sync: .unknown)
        #expect(state.isAwaitingHistory)
        #expect(!state.isVisible)
    }

    @Test("Stored activity short-circuits the wait")
    func storedActivityShortCircuits() {
        let state = Self.state(sync: .unknown, storedActivity: true)
        #expect(!state.isAwaitingHistory)
        #expect(state.isVisible)
    }

    @Test("An unreachable server ends the wait rather than hiding the row forever")
    func unavailableEndsTheWait() {
        #expect(Self.state(sync: .unavailable).isVisible)
    }
}
