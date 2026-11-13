//
//  GroupMoneyStaffStandingTests.swift
//  FlipcashTests
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

/// The staff value the Group Money gate reads before and after the server's
/// arrives, and what each launch keeps for the next one.
@Suite("Group Money staff standing") @MainActor
struct GroupMoneyStaffStandingTests {

    private let staff = UserID(uuidString: "00000000-0000-0000-0000-00000000000A")!
    private let other = UserID(uuidString: "00000000-0000-0000-0000-00000000000B")!

    // MARK: - Resolving

    @Test("A cold start for a known staff account reads the stored value before the server's arrives")
    func coldStartUsesLastKnown() {
        #expect(BetaFlags.staffStanding(live: nil, lastKnown: true))
    }

    @Test("The server's value wins over the stored one, in both directions")
    func liveWins() {
        #expect(!BetaFlags.staffStanding(live: false, lastKnown: true))
        #expect(BetaFlags.staffStanding(live: true, lastKnown: false))
        #expect(BetaFlags.staffStanding(live: true, lastKnown: nil))
    }

    @Test("With neither value the account is not staff")
    func unknownIsNotStaff() {
        #expect(!BetaFlags.staffStanding(live: nil, lastKnown: nil))
    }

    @Test("A non-staff account on a locked device with nothing stored gets neither the shell nor the toggle")
    func gateHoldsWithNothingStored() {
        let isStaff = BetaFlags.staffStanding(live: nil, lastKnown: nil)
        #expect(!BetaFlags.showsGroupMoneyUI(isEnabled: true, isStaff: isStaff, accessGranted: false))
        #expect(!BetaFlags.developerOptions(isStaff: isStaff, accessGranted: false).contains(.groupMoneyUI))
    }

    @Test("A cold start for a known staff account with the flag on shows the shell")
    func coldStartShowsShell() {
        let isStaff = BetaFlags.staffStanding(live: nil, lastKnown: true)
        #expect(BetaFlags.showsGroupMoneyUI(isEnabled: true, isStaff: isStaff, accessGranted: false))
    }

    // MARK: - Recording

    @Test("Nothing is recorded until the server's value arrives")
    func nilLeavesStoredValue() {
        let stored = [staff.uuidString: true]
        #expect(BetaFlags.recordingStaffStanding(nil, for: staff, in: stored) == stored)
    }

    @Test("The server's value replaces the stored one, including with false")
    func liveOverwrites() {
        let stored = [staff.uuidString: true]
        #expect(BetaFlags.recordingStaffStanding(false, for: staff, in: stored) == [staff.uuidString: false])
        #expect(BetaFlags.recordingStaffStanding(true, for: staff, in: [:]) == [staff.uuidString: true])
    }

    @Test("Each account keeps its own value, so another account on the device inherits nothing")
    func keyedByAccount() {
        let stored = BetaFlags.recordingStaffStanding(true, for: staff, in: [:])
        #expect(stored[other.uuidString] == nil)
        #expect(!BetaFlags.staffStanding(live: nil, lastKnown: stored[other.uuidString]))

        let both = BetaFlags.recordingStaffStanding(false, for: other, in: stored)
        #expect(both == [staff.uuidString: true, other.uuidString: false])
    }
}
