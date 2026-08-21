//
//  OnboardingFunnelStateTests.swift
//  FlipcashTests
//

import Foundation
import Testing
@testable import Flipcash

/// The wallet must not mistake a cold local cache for a brand-new account: on
/// every fresh login — switching accounts included — the history and both
/// onboarding milestones read empty until the first sync lands, and drawing that
/// verdict greets an established user with the new-user tutorial.
@Suite
@MainActor
struct OnboardingFunnelStateTests {

    private static func state(
        addedMoney: Bool = false,
        tipped: Bool = false,
        sync: HistoryController.SyncState = .synced,
        storedActivity: Bool = false
    ) -> OnboardingFunnelState {
        OnboardingFunnelState(
            hasAddedMoney: addedMoney,
            hasTipped: tipped,
            historySyncState: sync,
            hasStoredActivity: storedActivity
        )
    }

    @Test("The funnel is withheld while the history is still unsynced")
    func withheldBeforeFirstSync() {
        let state = Self.state(sync: .unknown)
        #expect(state.isAwaitingHistory)
        #expect(!state.isVisible)
    }

    @Test("The funnel shows once the history has synced and a milestone is outstanding")
    func shownAfterSync() {
        let state = Self.state(addedMoney: true, sync: .synced)
        #expect(!state.isAwaitingHistory)
        #expect(state.isVisible)
    }

    @Test("An unreachable server ends the wait rather than hiding the funnel forever")
    func unavailableEndsTheWait() {
        let state = Self.state(sync: .unavailable)
        #expect(!state.isAwaitingHistory)
        #expect(state.isVisible)
    }

    @Test("Stored activity short-circuits the wait — there is nothing to mistake for a new account")
    func storedActivityShortCircuits() {
        let state = Self.state(addedMoney: true, sync: .unknown, storedActivity: true)
        #expect(!state.isAwaitingHistory)
        #expect(state.isVisible)
    }

    @Test("A completed funnel is never drawn, synced or not")
    func completedIsHidden() {
        #expect(!Self.state(addedMoney: true, tipped: true, sync: .synced).isVisible)
        #expect(!Self.state(addedMoney: true, tipped: true, sync: .unknown).isVisible)
    }

    @Test("Milestones drive the step completion the funnel renders")
    func itemsCarryMilestones() {
        let state = Self.state(addedMoney: true, tipped: false)
        #expect(state.items == [.addMoney(isCompleted: true), .scanTipCard(isCompleted: false)])
        #expect(!state.isComplete)
    }
}
