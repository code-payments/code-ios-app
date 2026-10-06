//
//  ProfileMenuItemsTests.swift
//  FlipcashTests
//

import Testing
@testable import Flipcash

@MainActor
@Suite("ProfileMenuItems")
struct ProfileMenuItemsTests {

    @Test("A DM offers Mute, Report and Block")
    func dm_unmuted() {
        #expect(ProfileMenuItems.resolve(isBlocked: false, hasDM: true) == [.mute, .report, .block])
    }

    @Test("Without a DM there is nothing to mute")
    func noDM() {
        #expect(ProfileMenuItems.resolve(isBlocked: false, hasDM: false) == [.report, .block])
    }

    @Test("A blocked profile offers Report and Unblock, with no Mute", arguments: [true, false])
    func blocked(hasDM: Bool) {
        #expect(ProfileMenuItems.resolve(isBlocked: true, hasDM: hasDM) == [.report, .unblock])
    }

    @Test("Mute reads as in the chat mute row")
    func muteLabel() {
        #expect(ProfileMenuItem.mute.title == "Mute Notifications")
        #expect(ProfileMenuItem.mute.systemImage == "bell.slash")
    }

    @Test("Report and Block are destructive; Unblock and Mute are not")
    func destructive() {
        #expect(ProfileMenuItem.report.isDestructive)
        #expect(ProfileMenuItem.block.isDestructive)
        #expect(!ProfileMenuItem.unblock.isDestructive)
        #expect(!ProfileMenuItem.mute.isDestructive)
    }
}
