//
//  SettingsVersionCardStateTests.swift
//  FlipcashTests
//

import Testing
@testable import Flipcash

@Suite("SettingsVersionCardState")
struct SettingsVersionCardStateTests {

    private let newer = AppVersion("2026.10.4")!

    @Test("No newer version reads as up to date, inline, no dot")
    func upToDate() {
        let state = SettingsVersionCardState(newerVersion: nil, isDebugBuild: false)
        #expect(state == .upToDate)
        #expect(!state.isPinned)
        #expect(!state.showsGearDot)
        #expect(state.allowsBetaToggle)
    }

    @Test("A newer version pins the card, shows the dot, and drops the beta toggle")
    func updateAvailable() {
        let state = SettingsVersionCardState(newerVersion: newer, isDebugBuild: false)
        #expect(state == .updateAvailable(newer))
        #expect(state.isPinned)
        #expect(state.showsGearDot)
        #expect(!state.allowsBetaToggle)
    }

    @Test("A debug build stays inline with no dot even when a newer version exists")
    func debug() {
        for newerVersion in [nil, newer] {
            let state = SettingsVersionCardState(newerVersion: newerVersion, isDebugBuild: true)
            #expect(state == .debug)
            #expect(!state.isPinned)
            #expect(!state.showsGearDot)
        }
    }
}
