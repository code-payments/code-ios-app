//
//  BetaFlagsTests.swift
//  FlipcashTests
//

import Testing
@testable import Flipcash

// `.serialized` because every test drives the real `@Defaults`-backed store in
// `UserDefaults.standard` (see ContactSyncControllerTests for the same
// constraint), and constructs `BetaFlags` per simulated launch to exercise the
// read → apply defaults → apply overrides sequence the app runs at startup.
@Suite("BetaFlags", .serialized)
@MainActor
struct BetaFlagsTests {

    /// The options that ship on for a user who has never chosen. Derived rather
    /// than listed so the suite keeps covering whatever is currently default-on.
    static let defaultOn = BetaFlags.Option.allCases.filter(\.isOnByDefault)

    /// Clears both persisted keys, so each test starts from a fresh install.
    init() {
        var storedOptions = Defaults<Set<String>>(.betaFlags)
        var appliedDefaults = Defaults<Set<String>>(.appliedBetaFlagDefaults)
        storedOptions.wrappedValue = nil
        appliedDefaults.wrappedValue = nil
    }

    @Test("A fresh install starts the default-on flags on")
    func freshInstall_appliesDefaults() throws {
        try #require(!Self.defaultOn.isEmpty, "Nothing is default-on, so this suite proves nothing")

        let launch = BetaFlags()

        for option in Self.defaultOn {
            #expect(launch.hasEnabled(option), "\(option.rawValue) should start on")
        }
    }

    // MARK: - Launch argument overrides -

    @Test("An override replaces the whole set, so a default-on flag can run off")
    func override_replacesEntireSet() throws {
        let option = try #require(Self.defaultOn.first)
        let launch = BetaFlags()

        launch.applyLaunchArgumentOverrides(arguments: ["--beta-flags=vibrateOnScan"])

        #expect(launch.options == [.vibrateOnScan])
        #expect(!launch.hasEnabled(option))
    }

    @Test("An override with no argument clears every flag for that run")
    func overrideWithoutArgument_clearsEveryFlag() {
        let launch = BetaFlags()

        launch.applyLaunchArgumentOverrides(arguments: ["-ui-testing"])

        #expect(launch.options.isEmpty)
    }

    @Test("An override ignores names that are not options")
    func override_ignoresUnknownNames() {
        let launch = BetaFlags()

        launch.applyLaunchArgumentOverrides(arguments: ["--beta-flags=notAFlag,vibrateOnScan"])

        #expect(launch.options == [.vibrateOnScan])
    }

    // MARK: - Overrides do not outlive the run that set them -

    @Test("A named override leaves the default-on flags on for the next launch")
    func override_thenPlainLaunch_restoresDefaults() throws {
        try #require(!Self.defaultOn.isEmpty)

        let overridden = BetaFlags()
        overridden.applyLaunchArgumentOverrides(arguments: ["--beta-flags=vibrateOnScan"])

        let next = BetaFlags()

        for option in Self.defaultOn {
            #expect(next.hasEnabled(option), "\(option.rawValue) should be offered again")
        }
    }

    @Test("A UI test run that names no flags leaves the next launch its defaults")
    func overrideWithoutArgument_thenPlainLaunch_restoresDefaults() throws {
        try #require(!Self.defaultOn.isEmpty)

        // What every UI test launch does: AppDelegate calls this whenever
        // `isRunningUITests`, argument or not.
        let uiTestRun = BetaFlags()
        uiTestRun.applyLaunchArgumentOverrides(arguments: ["-ui-testing"])

        let next = BetaFlags()

        for option in Self.defaultOn {
            #expect(next.hasEnabled(option), "\(option.rawValue) should be offered again")
        }
    }

    // MARK: - A user's own choice still sticks -

    @Test("Turning a default-on flag off by hand survives a relaunch")
    func userTurnsDefaultOnFlagOff_staysOffAcrossLaunches() throws {
        let option = try #require(Self.defaultOn.first)

        let first = BetaFlags()
        first.set(option, enabled: false)

        let second = BetaFlags()

        #expect(!second.hasEnabled(option), "A default-on flag must not switch itself back on")
    }

    @Test("Turning a default-off flag on by hand survives a relaunch")
    func userTurnsFlagOn_staysOnAcrossLaunches() {
        let first = BetaFlags()
        first.set(.vibrateOnScan, enabled: true)

        let second = BetaFlags()

        #expect(second.hasEnabled(.vibrateOnScan))
    }
}
