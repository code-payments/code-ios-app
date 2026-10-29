//
//  NotificationStatusTests.swift
//  FlipcashCoreTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Testing
@testable import FlipcashCore

/// The notification status page's rules, one test per iOS row of the spec's Test cases table.
@Suite("Notification status")
struct NotificationStatusTests {

    private static let now = Date(timeIntervalSince1970: 1_793_200_000)
    private static let allowed = NotificationStatus.Snapshot(authorization: .authorized)

    private static func page(
        _ snapshot: NotificationStatus.Snapshot = allowed,
        registration: NotificationStatus.Registration = .finished(.ok),
        saved: NotificationStatus.RegistrationRecord? = nil,
        hasChecked: Bool = false
    ) -> NotificationStatus.Page {
        NotificationStatus.evaluate(
            snapshot: snapshot,
            registration: registration,
            saved: saved,
            hasChecked: hasChecked,
            now: now,
            locale: Locale(identifier: "en_US")
        )
    }

    private static func row(_ check: NotificationStatus.Check, in page: NotificationStatus.Page) -> NotificationStatus.Row? {
        page.rows.first { $0.check == check }
    }

    @Test("1: every check passes folds into one row and reads as working")
    func allPass() {
        let page = Self.page()

        #expect(page.summary.status == .pass)
        #expect(page.summary.title == "Notifications are working")
        #expect(page.summary.detail == "Checked just now")
        #expect(page.foldedTitle == "4 checks passed")
        #expect(page.rows.map(\.check) == [.permission, .display, .soundsAndBadges, .registration])
        #expect(page.isTestEnabled)
    }

    @Test("2: permission denied hides the display rows and disables the test")
    func permissionDenied() {
        let page = Self.page(.init(authorization: .denied))

        #expect(page.summary.status == .fail)
        #expect(page.summary.title == "Notifications are off")
        #expect(page.rows.map(\.check) == [.permission, .registration])
        #expect(Self.row(.permission, in: page)?.fix == .openNotificationSettings)
        #expect(Self.row(.permission, in: page)?.fixTitle == "Turn On")
        #expect(page.isTestEnabled == false)
        #expect(page.foldedTitle == nil)
    }

    @Test("3: notDetermined asks in the app rather than linking to Settings")
    func notDetermined() {
        let row = Self.row(.permission, in: Self.page(.init(authorization: .notDetermined)))

        #expect(row?.status == .fail)
        #expect(row?.title == "Notifications aren't turned on yet")
        #expect(row?.detail == "Flipcash hasn't asked yet")
        #expect(row?.fix == .requestAuthorization)
        #expect(row?.fixTitle == "Turn On")
    }

    @Test("4: banners off alone is one warning and the test stays enabled")
    func bannersOff() {
        let page = Self.page(.init(authorization: .authorized, alertStyle: .none))
        let row = Self.row(.display, in: page)

        #expect(row?.status == .warning)
        #expect(row?.title == "Banners are off")
        #expect(row?.fix == .openNotificationSettings)
        #expect(row?.fixTitle == "Fix")
        #expect(page.summary.status == .warning)
        #expect(page.summary.title == "1 thing to check")
        #expect(page.isTestEnabled)
        #expect(page.foldedTitle == nil)
    }

    @Test("Lock Screen off alone is its own warning")
    func lockScreenOff() {
        let row = Self.row(.display, in: Self.page(.init(authorization: .authorized, lockScreen: .disabled)))

        #expect(row?.status == .warning)
        #expect(row?.title == "Hidden on the Lock Screen")
    }

    @Test("Sounds and badges name what is off", arguments: [
        (NotificationStatus.Snapshot.Setting.disabled, NotificationStatus.Snapshot.Setting.enabled, "Sounds are off"),
        (.enabled, .disabled, "Badges are off"),
        (.disabled, .disabled, "Sounds and badges are off"),
    ])
    func soundsAndBadgesOff(sound: NotificationStatus.Snapshot.Setting, badge: NotificationStatus.Snapshot.Setting, title: String) {
        let row = Self.row(.soundsAndBadges, in: Self.page(.init(authorization: .authorized, sound: sound, badge: badge)))

        #expect(row?.status == .warning)
        #expect(row?.title == title)
    }

    @Test("10: an invalid push token fails and its retry deletes the local token first")
    func invalidPushToken() {
        let page = Self.page(registration: .finished(.invalidPushToken))
        let row = Self.row(.registration, in: page)

        #expect(row?.status == .fail)
        #expect(row?.title == "Flipcash rejected this phone's push token")
        #expect(row?.fix == .retryRegistrationDeletingToken)
        #expect(row?.fixTitle == "Try Again")
        #expect(page.summary.title == "1 thing to fix")
    }

    @Test("11: a timeout with no saved ok fails with a connection hint")
    func transportWithoutSavedOK() {
        let saved = NotificationStatus.RegistrationRecord(at: Self.now.addingTimeInterval(-600), result: .transport, source: .login)
        let row = Self.row(.registration, in: Self.page(registration: .finished(.transport), saved: saved))

        #expect(row?.status == .fail)
        #expect(row?.title == "Couldn't reach Flipcash")
        #expect(row?.detail == "Check your connection")
        #expect(row?.fix == .retryRegistration)
    }

    @Test("11b: a timeout after a past ok is only a warning")
    func transportWithSavedOK() {
        let saved = NotificationStatus.RegistrationRecord(at: Self.now.addingTimeInterval(-300), result: .ok, source: .refresh, lastRegistrationOkAt: Self.now.addingTimeInterval(-300))
        let page = Self.page(registration: .finished(.transport), saved: saved)
        let row = Self.row(.registration, in: page)

        #expect(row?.status == .warning)
        #expect(row?.title == "Couldn't reach Flipcash")
        #expect(row?.detail == "Last confirmed 5 minutes ago")
        #expect(page.summary.title == "1 thing to check")
    }

    @Test("A timeout after a failure that followed an ok is still a warning, dated by the ok")
    func transportAfterFailureFollowingOK() {
        let saved = NotificationStatus.RegistrationRecord(at: Self.now.addingTimeInterval(-60), result: .transport, source: .statusPage, lastRegistrationOkAt: Self.now.addingTimeInterval(-7200))
        let row = Self.row(.registration, in: Self.page(registration: .finished(.transport), saved: saved))

        #expect(row?.status == .warning)
        #expect(row?.detail == "Last confirmed 2 hours ago")
    }

    @Test("A save under a minute old reads just now, not 0 minutes ago", arguments: [0.0, -1, -59])
    func transportWithFreshSavedOK(offset: TimeInterval) {
        let saved = NotificationStatus.RegistrationRecord(at: Self.now.addingTimeInterval(offset), result: .ok, source: .refresh, lastRegistrationOkAt: Self.now.addingTimeInterval(offset))
        let page = Self.page(registration: .finished(.transport), saved: saved)

        #expect(Self.row(.registration, in: page)?.detail == "Last confirmed just now")
    }

    @Test("A save a minute old reads in minutes")
    func transportWithMinuteOldSavedOK() {
        let saved = NotificationStatus.RegistrationRecord(at: Self.now.addingTimeInterval(-60), result: .ok, source: .refresh, lastRegistrationOkAt: Self.now.addingTimeInterval(-60))
        let page = Self.page(registration: .finished(.transport), saved: saved)

        #expect(Self.row(.registration, in: page)?.detail == "Last confirmed 1 minute ago")
    }

    @Test("Group headers are title case")
    func groupTitles() {
        #expect(NotificationStatus.Group.phone.title == "On This Phone")
        #expect(NotificationStatus.Group.flipcash.title == "With Flipcash")
    }

    @Test("12: a registration in flight shows Checking on the row and the summary")
    func registrationInFlight() {
        let page = Self.page(registration: .checking)
        let row = Self.row(.registration, in: page)

        #expect(row?.status == .checking)
        #expect(row?.title == "Checking registration…")
        #expect(row?.detail == "Contacting Flipcash")
        #expect(page.summary.status == .checking)
        #expect(page.summary.title == "Checking…")
        #expect(page.foldedTitle == nil)
    }

    @Test("Before the settings are read, every check is listed as checking")
    func checkingPage() {
        let page = NotificationStatus.checkingPage()

        #expect(page.rows.map(\.check) == NotificationStatus.Check.allCases)
        #expect(page.rows.allSatisfy { $0.status == .checking })
        #expect(Self.row(.registration, in: page)?.title == "Checking registration…")
        #expect(page.summary.status == .checking)
        #expect(page.isTestEnabled == false)
        #expect(page.foldedTitle == nil)
    }

    @Test("A re-run keeps every row and its text, marked as checking, and the last summary")
    func recheckingKeepsRows() {
        let page = Self.page(.init(authorization: .denied), registration: .noAPNsToken)
        let rechecking = page.rechecking

        #expect(rechecking.rows.map(\.check) == page.rows.map(\.check))
        #expect(rechecking.rows.map(\.title) == page.rows.map(\.title))
        #expect(rechecking.rows.allSatisfy { $0.status == .checking })
        #expect(rechecking.summary == page.summary)
        #expect(rechecking.isTestEnabled == page.isTestEnabled)
    }

    @Test("The folded row passes, and shows Checking while the checks run again")
    func foldedRowRechecking() {
        let page = Self.page()
        #expect(page.foldedStatus == .pass)

        let rechecking = page.rechecking
        #expect(rechecking.foldedTitle == "4 checks passed")
        #expect(rechecking.foldedStatus == .checking)
    }

    @Test("A finished problem outranks a row still checking in the summary", arguments: [
        (NotificationStatus.Snapshot(authorization: .authorized, alertStyle: .none), NotificationStatus.Status.warning),
        (.init(authorization: .denied), .fail),
    ])
    func problemOutranksChecking(snapshot: NotificationStatus.Snapshot, expected: NotificationStatus.Status) {
        let page = Self.page(snapshot, registration: .checking)
        #expect(page.summary.status == expected)
        #expect(page.summary.detail == nil, "The second line waits for the first run to finish")
    }

    @Test("After the first run, a later run keeps Checked just now", arguments: [
        NotificationStatus.Snapshot(authorization: .authorized),
        .init(authorization: .authorized, alertStyle: .none),
        .init(authorization: .denied),
    ])
    func laterRunKeepsChecked(snapshot: NotificationStatus.Snapshot) {
        let page = Self.page(snapshot, registration: .checking, hasChecked: true)
        #expect(page.summary.detail == "Checked just now")
    }

    @Test("13: a fail outranks a warning in the summary")
    func failOutranksWarning() {
        let page = Self.page(.init(authorization: .authorized, alertStyle: .none), registration: .finished(.unknown))

        #expect(page.summary.status == .fail)
        #expect(page.summary.title == "1 thing to fix")
    }

    @Test("No APNs token fails the registration row")
    func noAPNsToken() {
        let page = Self.page(registration: .noAPNsToken)
        #expect(page.summary.title == "1 thing to fix")
        #expect(Self.row(.registration, in: page)?.title == "This phone isn't registered with Apple")
    }

    @Test("14: notSupported settings are not counted as off")
    func notSupported() {
        let snapshot = NotificationStatus.Snapshot(
            authorization: .authorized,
            alert: .notSupported,
            lockScreen: .notSupported,
            sound: .notSupported,
            badge: .notSupported
        )
        let page = Self.page(snapshot)

        #expect(page.summary.status == .pass)
        #expect(page.foldedTitle == "4 checks passed")
    }

    @Test("Rows keep check order within a group, failures included")
    func groupOrder() {
        let page = Self.page(.init(authorization: .authorized, alertStyle: .none), registration: .finished(.unknown))

        #expect(page.rows(in: .phone).map(\.check) == [.permission, .display, .soundsAndBadges])
        #expect(page.rows(in: .flipcash).map(\.check) == [.registration])
    }

    @Test("A failed test send is transport only when it never reached Flipcash")
    func testResult() {
        #expect(NotificationStatus.TestResult(.transportFailure) == .transport)
        #expect(NotificationStatus.TestResult(.cancelled) == .transport)
        #expect(NotificationStatus.TestResult(.unknown) == .failed)
        #expect(NotificationStatus.TestResult(.rejected) == .failed)
    }

    @Test("The report lists every check with its raw value and no full token")
    func report() throws {
        let saved = NotificationStatus.RegistrationRecord(at: Self.now, result: .ok, source: .statusPage, lastRegistrationOkAt: Self.now)
        let timeZone = try #require(TimeZone(secondsFromGMT: -4 * 3600))
        let report = NotificationStatus.report(
            snapshot: .init(authorization: .denied, alertStyle: .none),
            registration: .finished(.ok),
            saved: saved,
            context: .init(appVersion: "3.4.1 (812)", osVersion: "26.1", deviceModel: "iPhone17,1", tokenSuffix: "a1b2c3", lastAPNsError: nil),
            now: Self.now,
            timeZone: timeZone
        )

        #expect(report == """
            Flipcash notification report
            2026-10-28 11:06 (UTC-4)
            App 3.4.1 (812) · iOS 26.1 · iPhone17,1

            Notifications allowed: fail (denied)
            Banners and Lock Screen: warning (alertStyle none)
            Sounds and badges: pass
            Registered for push: pass (statusPage, 2026-10-28 11:06)
            Last ok: 2026-10-28 11:06

            Token: …a1b2c3 (last 6)
            Last APNs error: none
            """)
    }

    @Test("The report describes this page's run, then the last ok on its own line", arguments: [
        (NotificationStatus.Registration.finished(.transport), NotificationStatus.RegistrationRecord(at: NotificationStatusTests.now, result: .transport, source: .statusPage), String?("a1b2c3"), "Registered for push: fail (transport, statusPage, 2026-10-28 11:06)", "Last ok: never", "Token: …a1b2c3 (last 6)"),
        (.noAPNsToken, .init(at: NotificationStatusTests.now, result: .ok, source: .login, lastRegistrationOkAt: NotificationStatusTests.now), nil, "Registered for push: fail (noAPNsToken)", "Last ok: 2026-10-28 11:06", "Token: none"),
        (.checking, .init(at: NotificationStatusTests.now, result: .ok, source: .login, lastRegistrationOkAt: NotificationStatusTests.now), nil, "Registered for push: checking", "Last ok: 2026-10-28 11:06", "Token: none"),
    ])
    func reportRegistration(
        registration: NotificationStatus.Registration,
        saved: NotificationStatus.RegistrationRecord,
        tokenSuffix: String?,
        line: String,
        lastOK: String,
        token: String
    ) throws {
        let report = NotificationStatus.report(
            snapshot: Self.allowed,
            registration: registration,
            saved: saved,
            context: .init(appVersion: "1", osVersion: "26.1", deviceModel: "iPhone17,1", tokenSuffix: tokenSuffix, lastAPNsError: nil),
            now: Self.now,
            timeZone: try #require(TimeZone(secondsFromGMT: -4 * 3600))
        )
        let lines = report.split(separator: "\n").map(String.init)

        let index = try #require(lines.firstIndex(of: line))
        #expect(lines[index + 1] == lastOK)
        #expect(lines.contains(token))
    }

    @Test("UTC offsets keep half hours and write zero as UTC+0")
    func utcOffset() throws {
        let india = try #require(TimeZone(secondsFromGMT: 5 * 3600 + 1800))
        #expect(NotificationStatus.utcOffset(india, at: Self.now) == "UTC+5:30")
        #expect(NotificationStatus.utcOffset(try #require(TimeZone(secondsFromGMT: 0)), at: Self.now) == "UTC+0")
    }

    @Test("AddToken errors classify as the spec's results", arguments: [
        (ErrorAddToken.invalidPushToken, NotificationStatus.RegistrationResult.invalidPushToken),
        (.transportFailure, .transport),
        (.cancelled, .transport),
        (.rejected, .unknown),
        (.unknown, .unknown),
    ])
    func addTokenErrors(error: ErrorAddToken, expected: NotificationStatus.RegistrationResult) {
        #expect(NotificationStatus.RegistrationResult(error) == expected)
    }

    @Test("The saved registration is kept per account and cleared on logout")
    func registrationStore() throws {
        let defaults = try #require(UserDefaults(suiteName: "NotificationStatusTests.\(UUID())"))
        let store = NotificationRegistrationStore(defaults: defaults, owner: KeyPair.mock.publicKey)
        let record = NotificationStatus.RegistrationRecord(at: Self.now, result: .transport, source: .refresh)

        #expect(store.record == nil)
        store.record = record
        #expect(NotificationRegistrationStore(defaults: defaults, owner: KeyPair.mock.publicKey).record == record)

        store.clear()
        #expect(store.record == nil)
    }

    @Test("Saving keeps the last ok time until a newer ok, and logout clears it")
    func registrationStoreKeepsLastOK() throws {
        let defaults = try #require(UserDefaults(suiteName: "NotificationStatusTests.\(UUID())"))
        let store = NotificationRegistrationStore(defaults: defaults, owner: KeyPair.mock.publicKey)
        let first = Self.now.addingTimeInterval(-3600)
        let second = Self.now.addingTimeInterval(-600)

        store.save(.transport, source: .login, at: first.addingTimeInterval(-60))
        #expect(store.record?.lastRegistrationOkAt == nil)

        store.save(.ok, source: .login, at: first)
        store.save(.transport, source: .statusPage, at: first.addingTimeInterval(60))
        store.save(.invalidPushToken, source: .refresh, at: first.addingTimeInterval(120))
        #expect(store.record?.result == .invalidPushToken)
        #expect(store.record?.lastRegistrationOkAt == first)

        store.save(.ok, source: .statusPage, at: second)
        #expect(store.record?.lastRegistrationOkAt == second)

        store.clear()
        #expect(store.record == nil)
    }

    @Test("A record saved before the last ok time existed still loads")
    func registrationRecordWithoutLastOK() throws {
        let json = Data(#"{"at":0,"result":"ok","source":"login"}"#.utf8)
        let record = try JSONDecoder().decode(NotificationStatus.RegistrationRecord.self, from: json)

        #expect(record.result == .ok)
        #expect(record.lastRegistrationOkAt == nil)
    }
}
