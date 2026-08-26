//
//  VersionTapUnlockTests.swift
//  FlipcashTests
//

import Foundation
import Testing
@testable import Flipcash

@MainActor
@Suite("Version footer tap unlock")
struct VersionTapUnlockTests {

    /// Taps `count` times against a locked state, reporting how many taps
    /// toggled and the message left standing.
    private func tap(_ unlock: VersionTapUnlock, times count: Int, isUnlocked: Bool = false) -> Int {
        var toggles = 0
        for _ in 0..<count {
            unlock.registerTap(isUnlocked: isUnlocked) { toggles += 1 }
        }
        return toggles
    }

    @Test("The first taps say nothing")
    func earlyTaps_areSilent() {
        let unlock = VersionTapUnlock()
        #expect(tap(unlock, times: 6) == 0)
        #expect(unlock.message == nil)
    }

    @Test("The countdown starts three taps out")
    func countdown_startsThreeTapsOut() {
        let unlock = VersionTapUnlock()

        _ = tap(unlock, times: 7)
        #expect(unlock.message == "You are now 3 steps away from being a developer")

        _ = tap(unlock, times: 1)
        #expect(unlock.message == "You are now 2 steps away from being a developer")
    }

    @Test("The last tap before the unlock is singular")
    func countdown_lastTapIsSingular() {
        let unlock = VersionTapUnlock()
        _ = tap(unlock, times: 9)
        #expect(unlock.message == "You are now 1 step away from being a developer")
    }

    @Test("The tenth tap unlocks and says so")
    func tenthTap_unlocks() {
        let unlock = VersionTapUnlock()
        #expect(tap(unlock, times: 10) == 1)
        #expect(unlock.message == "You are now a developer!")
    }

    @Test("Ten more taps lock it again")
    func tenMoreTaps_lockAgain() {
        let unlock = VersionTapUnlock()

        #expect(tap(unlock, times: 10) == 1)
        #expect(tap(unlock, times: 9, isUnlocked: true) == 0)
        #expect(unlock.message == "You are now 1 step away from hiding beta features")

        #expect(tap(unlock, times: 1, isUnlocked: true) == 1)
        #expect(unlock.message == "Beta features are hidden again")
    }
}
