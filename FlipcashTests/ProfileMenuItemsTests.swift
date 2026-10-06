//
//  ProfileMenuItemsTests.swift
//  FlipcashTests
//

import Testing
@testable import Flipcash

@MainActor
@Suite("ProfileMenuItems")
struct ProfileMenuItemsTests {

    @Test("A DM that is audible offers Mute, Report and Block")
    func dm_unmuted() {
        #expect(ProfileMenuItems.resolve(isBlocked: false, hasDM: true, isMuted: false) == [.mute, .report, .block])
    }

    @Test("A muted DM offers Unmute in Mute's place")
    func dm_muted() {
        #expect(ProfileMenuItems.resolve(isBlocked: false, hasDM: true, isMuted: true) == [.unmute, .report, .block])
    }

    @Test("Without a DM there is nothing to mute")
    func noDM() {
        #expect(ProfileMenuItems.resolve(isBlocked: false, hasDM: false, isMuted: false) == [.report, .block])
    }

    @Test("A blocked profile offers Report and Unblock, with no Mute", arguments: [true, false])
    func blocked(hasDM: Bool) {
        #expect(ProfileMenuItems.resolve(isBlocked: true, hasDM: hasDM, isMuted: false) == [.report, .unblock])
    }

    @Test("Report, Block and Unblock are destructive; Unblock and the mutes are not")
    func destructive() {
        #expect(ProfileMenuItem.report.isDestructive)
        #expect(ProfileMenuItem.block.isDestructive)
        #expect(!ProfileMenuItem.unblock.isDestructive)
        #expect(!ProfileMenuItem.mute.isDestructive)
        #expect(!ProfileMenuItem.unmute.isDestructive)
    }
}
