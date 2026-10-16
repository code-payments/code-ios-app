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

    @Test("A debug build stays inline with no dot even when a newer version or build exists")
    func debug() {
        for newerVersion in [nil, newer] {
            let state = SettingsVersionCardState(
                newerVersion: newerVersion,
                isDebugBuild: true,
                channel: .testFlight,
                installedBuild: 272,
                latestTestFlightBuild: 281,
                isStaff: true
            )
            #expect(state == .debug(latestTestFlightBuild: 281))
            #expect(!state.isPinned)
            #expect(!state.showsGearDot)
        }
    }

    @Test("A debug build without a manifest has no latest build")
    func debugWithoutManifest() {
        let state = SettingsVersionCardState(newerVersion: nil, isDebugBuild: true, channel: .other)
        #expect(state == .debug(latestTestFlightBuild: nil))
    }

    @Test("A TestFlight install with a newer build pins the card and shows the dot")
    func testFlightUpdate() {
        let state = SettingsVersionCardState(
            newerVersion: nil, isDebugBuild: false, channel: .testFlight, installedBuild: 272, latestTestFlightBuild: 281
        )
        #expect(state == .testFlightUpdate(build: 281))
        #expect(state.isPinned)
        #expect(state.showsGearDot)
    }

    @Test("A TestFlight install on the latest build is up to date")
    func testFlightCurrent() {
        for latest in [272, 260] {
            let state = SettingsVersionCardState(
                newerVersion: nil, isDebugBuild: false, channel: .testFlight, installedBuild: 272, latestTestFlightBuild: latest
            )
            #expect(state == .upToDate)
        }
    }

    @Test("A TestFlight install does not need staff")
    func testFlightUpdateIgnoresStaff() {
        let state = SettingsVersionCardState(
            newerVersion: nil, isDebugBuild: false, channel: .testFlight, installedBuild: 272, latestTestFlightBuild: 281, isStaff: false
        )
        #expect(state == .testFlightUpdate(build: 281))
    }

    @Test("A store update wins over a newer TestFlight build")
    func storeWins() {
        let state = SettingsVersionCardState(
            newerVersion: newer, isDebugBuild: false, channel: .store, installedBuild: 272, latestTestFlightBuild: 281, isStaff: true
        )
        #expect(state == .updateAvailable(newer))
    }

    @Test("Staff on a store build are told a newer TestFlight build exists, with no dot")
    func staffNewer() {
        let state = SettingsVersionCardState(
            newerVersion: nil, isDebugBuild: false, channel: .store, installedBuild: 272, latestTestFlightBuild: 281, isStaff: true
        )
        #expect(state == .testFlightNewer(build: 281))
        #expect(state.isPinned)
        #expect(!state.showsGearDot)
    }

    @Test("Everyone else on a store build never hears about TestFlight")
    func nonStaffStoreBuild() {
        let state = SettingsVersionCardState(
            newerVersion: nil, isDebugBuild: false, channel: .store, installedBuild: 272, latestTestFlightBuild: 281, isStaff: false
        )
        #expect(state == .upToDate)
    }

    @Test("Staff on a store build with no newer TestFlight build see the plain card")
    func staffNothingNewer() {
        for latest in [nil, 272, 260] {
            let state = SettingsVersionCardState(
                newerVersion: nil, isDebugBuild: false, channel: .store, installedBuild: 272, latestTestFlightBuild: latest, isStaff: true
            )
            #expect(state == .upToDate)
        }
    }

    @Test("Only internal, debug and staff cards put the build in the title")
    func titleBuild() {
        #expect(SettingsVersionCardState.testFlightUpdate(build: 1).titleShowsBuild)
        #expect(SettingsVersionCardState.testFlightNewer(build: 1).titleShowsBuild)
        #expect(SettingsVersionCardState.debug(latestTestFlightBuild: nil).titleShowsBuild)
        #expect(!SettingsVersionCardState.upToDate.titleShowsBuild)
        #expect(!SettingsVersionCardState.updateAvailable(newer).titleShowsBuild)
    }
}
