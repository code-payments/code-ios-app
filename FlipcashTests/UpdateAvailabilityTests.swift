//
//  UpdateAvailabilityTests.swift
//  FlipcashTests
//

import Foundation
import Testing
import FlipcashUI
@testable import Flipcash

@Suite struct AppVersionTests {

    @Test func comparesEachComponentNumerically() {
        #expect(AppVersion("2026.10.10")! > AppVersion("2026.10.9")!)
        #expect(AppVersion("2026.9.30")! < AppVersion("2026.10.1")!)
        #expect(AppVersion("2027.1.0")! > AppVersion("2026.12.31")!)
    }

    @Test func missingTrailingComponentsReadAsZero() {
        #expect(AppVersion("2026.10")! == AppVersion("2026.10.0")!)
        #expect(AppVersion("2026.10.1")! > AppVersion("2026.10")!)
    }

    @Test(arguments: ["", "2026.x.1", "2026..1", "1.-2", "v2026.10.1"])
    func rejectsMalformed(_ string: String) {
        #expect(AppVersion(string) == nil)
    }
}

@Suite struct UpdateCheckParsingTests {

    @Test func lookupReadsTheFirstResult() {
        let data = Data("""
        {"resultCount":1,"results":[{"version":"2026.10.4","currentVersionReleaseDate":"2026-10-08T17:02:11Z"}]}
        """.utf8)
        let release = StoreRelease.parseLookup(data)
        #expect(release?.version == AppVersion("2026.10.4"))
        #expect(release?.releasedAt == ISO8601DateFormatter().date(from: "2026-10-08T17:02:11Z"))
    }

    @Test func lookupWithNoResultsIsNil() {
        #expect(StoreRelease.parseLookup(Data(#"{"resultCount":0,"results":[]}"#.utf8)) == nil)
        #expect(StoreRelease.parseLookup(Data("not json".utf8)) == nil)
    }

    @Test func lookupURLNamesTheAppAndStorefront() {
        let url = StoreRelease.lookupURL(country: "CA").absoluteString
        #expect(url == "https://itunes.apple.com/lookup?id=6758636374&country=ca")
    }

    @Test func manifestPriorityAppliesOnlyToItsVersion() {
        let data = Data("""
        {"updated":"2026-10-14T00:00:00Z","production":{"version":"2026.10.4","priority":5}}
        """.utf8)
        let manifest = ReleaseManifest.parse(data)
        #expect(manifest?.priority(for: AppVersion("2026.10.4")!) == 5)
        #expect(manifest?.priority(for: AppVersion("2026.10.5")!) == 0)
    }

    @Test func malformedManifestIsNil() {
        #expect(ReleaseManifest.parse(Data(#"{"production":{"version":"x","priority":1}}"#.utf8)) == nil)
    }
}

@Suite struct UpdateEligibilityTests {

    private let now = Date(timeIntervalSince1970: 1_000_000_000)
    private let installed = AppVersion("2026.10.3")

    private func result(version: String = "2026.10.4", daysOut: Double, priority: Int = 0) -> UpdateCheckResult {
        UpdateCheckResult(
            release: StoreRelease(version: AppVersion(version)!, releasedAt: now.addingTimeInterval(-daysOut * 86_400)),
            priority: priority,
            checkedAt: now
        )
    }

    private func eligible(_ result: UpdateCheckResult?, shown: String? = nil) -> Bool {
        UpdateEligibility.isToastEligible(
            installed: installed,
            result: result,
            lastShownVersion: shown.flatMap(AppVersion.init),
            now: now
        )
    }

    @Test func freshOptionalUpdateWaits() {
        #expect(!eligible(result(daysOut: 6.9)))
    }

    @Test func updateOutForSevenDaysIsEligible() {
        #expect(eligible(result(daysOut: 7)))
    }

    @Test func priorityUpdateIsEligibleAtOnce() {
        #expect(eligible(result(daysOut: 0, priority: 4)))
        #expect(!eligible(result(daysOut: 0, priority: 3)))
    }

    @Test func showsOncePerVersion() {
        #expect(!eligible(result(daysOut: 30), shown: "2026.10.4"))
        #expect(eligible(result(version: "2026.10.5", daysOut: 30), shown: "2026.10.4"))
    }

    @Test func sameOrOlderStoreVersionIsNoUpdate() {
        #expect(!eligible(result(version: "2026.10.3", daysOut: 30, priority: 5)))
        #expect(!eligible(result(version: "2026.10.2", daysOut: 30, priority: 5)))
        #expect(UpdateEligibility.newerVersion(installed: installed, release: result(version: "2026.10.2", daysOut: 1).release) == nil)
    }

    @Test func noResultIsNoUpdate() {
        #expect(!eligible(nil))
    }
}

@MainActor
@Suite struct UpdateAvailabilityTests {

    private let defaults = UserDefaults(suiteName: "update-availability-\(UUID())")!
    private let now = ISO8601DateFormatter().date(from: "2026-10-14T12:00:00Z")!

    private static let staleLookup = Data("""
    {"results":[{"version":"2026.10.4","currentVersionReleaseDate":"2026-10-01T00:00:00Z"}]}
    """.utf8)

    private func sut(
        channel: InstallChannel = .store,
        lookup: Data = staleLookup,
        manifest: Data? = nil,
        at date: Date? = nil,
        installChannel: (() async -> InstallChannel?)? = nil,
        channelLookupTimeout: Duration = .seconds(10)
    ) -> UpdateAvailability {
        let time = date ?? now
        return UpdateAvailability(
            installedVersion: "2026.10.3",
            defaults: defaults,
            now: { time },
            fetch: { url in
                if url == ReleaseManifest.url {
                    guard let manifest else { throw URLError(.fileDoesNotExist) }
                    return manifest
                }
                return lookup
            },
            installChannel: installChannel ?? { channel },
            channelLookupTimeout: channelLookupTimeout
        )
    }

    private static let testFlightManifest = Data(
        #"{"production":{"version":"2026.10.2","priority":0},"testflight":{"build":281}}"#.utf8
    )

    @Test func storeBuildFindsTheNewerVersion() async {
        let updates = sut()
        await updates.check()
        #expect(updates.newerVersion == AppVersion("2026.10.4"))
        #expect(updates.isToastEligible)
    }

    @Test func nonStoreBuildNeverReportsAnUpdate() async {
        let updates = sut(channel: .other)
        await updates.check()
        #expect(updates.newerVersion == nil)
        #expect(!updates.isToastEligible)
    }

    @Test func testFlightBuildComesFromTheManifestOnEveryChannel() async {
        let manifest = Data(#"{"production":{"version":"2026.10.2","priority":0},"testflight":{"build":281}}"#.utf8)
        for channel in [InstallChannel.store, .testFlight, .other] {
            let updates = sut(channel: channel, manifest: manifest)
            await updates.check()
            #expect(updates.latestTestFlightBuild == 281)
            #expect(updates.channel == channel)
        }
    }

    @Test func testFlightInstallNeverLooksUpTheStore() async {
        let manifest = Data(#"{"production":{"version":"2026.10.2","priority":0},"testflight":{"build":281}}"#.utf8)
        let updates = sut(channel: .testFlight, manifest: manifest)
        await updates.check()
        #expect(updates.newerVersion == nil)
        #expect(updates.latestTestFlightBuild == 281)
    }

    @Test func channelAndTestFlightBuildSurviveRelaunch() async {
        let manifest = Data(#"{"production":{"version":"2026.10.2","priority":0},"testflight":{"build":281}}"#.utf8)
        await sut(channel: .testFlight, manifest: manifest).check()
        let relaunched = sut(channel: .testFlight)
        #expect(relaunched.channel == .testFlight)
        #expect(relaunched.latestTestFlightBuild == 281)
    }

    @Test func hungChannelLookupStillReadsTheManifest() async {
        await sut(channel: .testFlight).check()
        let updates = sut(
            manifest: Self.testFlightManifest,
            installChannel: {
                try? await Task.sleep(for: .seconds(3600))
                return .store
            },
            channelLookupTimeout: .milliseconds(50)
        )
        await updates.check()
        #expect(updates.latestTestFlightBuild == 281)
        #expect(updates.channel == .testFlight)
    }

    @Test func failedChannelLookupKeepsTheLastKnownChannel() async {
        await sut(channel: .testFlight).check()
        let updates = sut(manifest: Self.testFlightManifest, installChannel: { nil })
        await updates.check()
        #expect(updates.channel == .testFlight)
        #expect(sut(channel: .store).channel == .testFlight)
    }

    @Test func failedChannelLookupWithNoHistoryIsOther() async {
        let updates = sut(manifest: Self.testFlightManifest, installChannel: { nil })
        await updates.check()
        #expect(updates.channel == .other)
        #expect(updates.latestTestFlightBuild == 281)
    }

    @Test func manifestWithoutTestFlightLeavesTheBuildUnknown() async {
        let manifest = Data(#"{"production":{"version":"2026.10.2","priority":0}}"#.utf8)
        let updates = sut(manifest: manifest)
        await updates.check()
        #expect(updates.latestTestFlightBuild == nil)
        #expect(ReleaseManifest.parse(manifest)?.testFlightBuild == nil)
    }

    @Test func failedLookupIsNoUpdate() async {
        let updates = UpdateAvailability(
            installedVersion: "2026.10.3",
            defaults: defaults,
            now: { now },
            fetch: { _ in throw URLError(.notConnectedToInternet) },
            installChannel: { .store }
        )
        await updates.check()
        #expect(updates.newerVersion == nil)
    }

    @Test func manifestPriorityMakesAFreshUpdateEligible() async {
        let fresh = Data("""
        {"results":[{"version":"2026.10.4","currentVersionReleaseDate":"2026-10-13T00:00:00Z"}]}
        """.utf8)
        let manifest = Data(#"{"production":{"version":"2026.10.4","priority":4}}"#.utf8)
        let plain = sut(lookup: fresh)
        await plain.check()
        #expect(plain.newerVersion != nil)
        #expect(!plain.isToastEligible)

        let urgent = sut(lookup: fresh, manifest: manifest)
        await urgent.check()
        #expect(urgent.isToastEligible)
    }

    @Test func refreshWithinTheIntervalSkipsUnlessResumingFromBackground() async {
        let updates = sut()
        await updates.check()
        #expect(!updates.refresh())

        updates.appDidEnterBackground()
        #expect(updates.refresh())
    }

    @Test func resultSurvivesRelaunch() async {
        await sut().check()
        #expect(sut().newerVersion == AppVersion("2026.10.4"))
    }

    @Test func showingTheToastMarksItsVersionSeen() async {
        let updates = sut()
        await updates.check()
        let toasts = ToastController()
        #expect(updates.showToastIfEligible(on: toasts, timeout: .seconds(10)))
        #expect(toasts.current != nil)
        #expect(!updates.isToastEligible)
        #expect(!sut().isToastEligible)
        #expect(!updates.showToastIfEligible(on: toasts, timeout: .seconds(10)))
    }

    @Test func toastDroppedWhileCoveredIsNotSeen() async {
        let updates = sut()
        await updates.check()
        let toasts = ToastController()
        toasts.isCovered = true
        #expect(!updates.showToastIfEligible(on: toasts, timeout: .seconds(10)))
        #expect(updates.isToastEligible)
    }

    @Test func dismissRemovesOnlyTheUpdateToast() async {
        let updates = sut()
        await updates.check()
        let toasts = ToastController()
        updates.showToastIfEligible(on: toasts, timeout: .seconds(10))
        updates.dismissToast(on: toasts)
        #expect(toasts.current == nil)

        toasts.show(.init("Copied"))
        updates.dismissToast(on: toasts)
        #expect(toasts.current != nil)
    }
}
