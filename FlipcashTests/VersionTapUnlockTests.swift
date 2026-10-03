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

    /// Taps `count` times, reporting how many taps toggled and the line the
    /// last tap asked to show.
    private func tap(
        _ unlock: VersionTapUnlock,
        times count: Int,
        isUnlocked: Bool = false
    ) -> (toggles: Int, message: String?) {
        var toggles = 0
        var message: String?
        for _ in 0..<count {
            message = unlock.registerTap(isUnlocked: isUnlocked) { toggles += 1 }
        }
        return (toggles, message)
    }

    @Test("The first taps say nothing")
    func earlyTaps_areSilent() {
        let unlock = VersionTapUnlock()
        let result = tap(unlock, times: 6)
        #expect(result.toggles == 0)
        #expect(result.message == nil)
    }

    @Test("The countdown starts three taps out")
    func countdown_startsThreeTapsOut() {
        let unlock = VersionTapUnlock()

        #expect(tap(unlock, times: 7).message == "You are now 3 steps away from being a developer")
        #expect(tap(unlock, times: 1).message == "You are now 2 steps away from being a developer")
    }

    @Test("The last tap before the unlock is singular")
    func countdown_lastTapIsSingular() {
        let unlock = VersionTapUnlock()
        #expect(tap(unlock, times: 9).message == "You are now 1 step away from being a developer")
    }

    @Test("The tenth tap unlocks and says so")
    func tenthTap_unlocks() {
        let unlock = VersionTapUnlock()
        let result = tap(unlock, times: 10)
        #expect(result.toggles == 1)
        #expect(result.message == "You are now a developer!")
    }

    @Test("Ten more taps lock it again")
    func tenMoreTaps_lockAgain() {
        let unlock = VersionTapUnlock()

        #expect(tap(unlock, times: 10).toggles == 1)

        let nearlyLocked = tap(unlock, times: 9, isUnlocked: true)
        #expect(nearlyLocked.toggles == 0)
        #expect(nearlyLocked.message == "You are now 1 step away from hiding beta features")

        let locked = tap(unlock, times: 1, isUnlocked: true)
        #expect(locked.toggles == 1)
        #expect(locked.message == "Beta features are hidden again")
    }
}
