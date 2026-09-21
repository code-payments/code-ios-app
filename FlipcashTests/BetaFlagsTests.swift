//
//  BetaFlagsTests.swift
//  FlipcashTests
//

import Testing
@testable import Flipcash

/// The options that ship on for a user who has never chosen. Derived rather than
/// listed so the suite keeps covering whatever is currently default-on.
///
/// File-scope because ``needsADefaultOnOption`` reads it from a trait, which is
/// evaluated outside the suite's instance scope.
@MainActor private let defaultOnOptions = BetaFlags.Option.allCases.filter(\.isOnByDefault)

/// Gates the tests that need a flag to be default-on. Nothing is, at the moment,
/// so they skip rather than fail or pass over an empty set — and they come back
/// the next time a flag ships that way.
///
/// The async `.enabled` form rather than `.enabled(if:)`: `Option` is `@MainActor`
/// under the project's default isolation, and only the async condition can await it.
private let needsADefaultOnOption = ConditionTrait.enabled("No flag ships on by default") {
    !(await defaultOnOptions.isEmpty)
}

// `.serialized` because every test drives the real `@Defaults`-backed store in
// `UserDefaults.standard` (see ContactSyncControllerTests for the same
// constraint), and constructs `BetaFlags` per simulated launch to exercise the
// read → apply defaults → apply overrides sequence the app runs at startup.
@Suite("BetaFlags", .serialized)
@MainActor
struct BetaFlagsTests {

    /// Clears both persisted keys, so each test starts from a fresh install.
    init() {
        var storedOptions = Defaults<Set<String>>(.betaFlags)
        var appliedDefaults = Defaults<Set<String>>(.appliedBetaFlagDefaults)
        storedOptions.wrappedValue = nil
        appliedDefaults.wrappedValue = nil
    }

    @Test("A fresh install starts the default-on flags on", needsADefaultOnOption)
    func freshInstall_appliesDefaults() {
        let launch = BetaFlags()

        for option in defaultOnOptions {
            #expect(launch.hasEnabled(option), "\(option.rawValue) should start on")
        }
    }

    // MARK: - Launch argument overrides -

    @Test("An override replaces the whole set, so a default-on flag can run off", needsADefaultOnOption)
    func override_replacesEntireSet() throws {
        let option = try #require(defaultOnOptions.first)
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

    @Test("A named override leaves the default-on flags on for the next launch", needsADefaultOnOption)
    func override_thenPlainLaunch_restoresDefaults() {
        let overridden = BetaFlags()
        overridden.applyLaunchArgumentOverrides(arguments: ["--beta-flags=vibrateOnScan"])

        let next = BetaFlags()

        for option in defaultOnOptions {
            #expect(next.hasEnabled(option), "\(option.rawValue) should be offered again")
        }
    }

    @Test("A UI test run that names no flags leaves the next launch its defaults", needsADefaultOnOption)
    func overrideWithoutArgument_thenPlainLaunch_restoresDefaults() {
        // What every UI test launch does: AppDelegate calls this whenever
        // `isRunningUITests`, argument or not.
        let uiTestRun = BetaFlags()
        uiTestRun.applyLaunchArgumentOverrides(arguments: ["-ui-testing"])

        let next = BetaFlags()

        for option in defaultOnOptions {
            #expect(next.hasEnabled(option), "\(option.rawValue) should be offered again")
        }
    }

    // MARK: - A user's own choice still sticks -

    @Test("Turning a default-on flag off by hand survives a relaunch", needsADefaultOnOption)
    func userTurnsDefaultOnFlagOff_staysOffAcrossLaunches() throws {
        let option = try #require(defaultOnOptions.first)

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
