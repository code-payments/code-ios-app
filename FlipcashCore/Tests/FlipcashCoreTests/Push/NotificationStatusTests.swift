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
        saved: NotificationStatus.RegistrationRecord? = nil
    ) -> NotificationStatus.Page {
        NotificationStatus.evaluate(
            snapshot: snapshot,
            registration: registration,
            saved: saved,
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
        #expect(Self.row(.permission, in: page)?.fixTitle == "Turn on")
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
        #expect(row?.fixTitle == "Turn on")
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
        #expect(row?.fixTitle == "Try again")
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

    @Test("11b: a timeout after a saved ok is only a warning")
    func transportWithSavedOK() {
        let saved = NotificationStatus.RegistrationRecord(at: Self.now.addingTimeInterval(-300), result: .ok, source: .refresh)
        let page = Self.page(registration: .finished(.transport), saved: saved)
        let row = Self.row(.registration, in: page)

        #expect(row?.status == .warning)
        #expect(row?.title == "Couldn't reach Flipcash")
        #expect(row?.detail == "Last confirmed 5 minutes ago")
        #expect(page.summary.title == "1 thing to check")
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

    @Test("An interrupted registration offers Try again")
    func interrupted() {
        let page = Self.page(registration: .interrupted)
        let row = Self.row(.registration, in: page)

        #expect(row?.status == .unknown)
        #expect(row?.detail == "Check was interrupted")
        #expect(row?.fix == .retryRegistration)
        #expect(page.summary.status == .unknown)
    }

    @Test("Rows keep check order within a group, failures included")
    func groupOrder() {
        let page = Self.page(.init(authorization: .authorized, alertStyle: .none), registration: .finished(.unknown))

        #expect(page.rows(in: .phone).map(\.check) == [.permission, .display, .soundsAndBadges])
        #expect(page.rows(in: .flipcash).map(\.check) == [.registration])
    }

    @Test("The test notification is recognised by its flag alone")
    func testNotificationFlag() {
        #expect(NotificationStatus.isTestNotification([NotificationStatus.testUserInfoKey: true]))
        #expect(NotificationStatus.isTestNotification([:]) == false)
        #expect(NotificationStatus.isTestNotification([NotificationStatus.testUserInfoKey: false]) == false)
    }

    @Test("The report lists every check with its raw value and no full token")
    func report() throws {
        let saved = NotificationStatus.RegistrationRecord(at: Self.now, result: .ok, source: .statusPage)
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

            Token: …a1b2c3 (last 6)
            Last APNs error: none
            """)
    }

    @Test("UTC offsets keep half hours")
    func utcOffset() throws {
        let india = try #require(TimeZone(secondsFromGMT: 5 * 3600 + 1800))
        #expect(NotificationStatus.utcOffset(india, at: Self.now) == "UTC+5:30")
        #expect(NotificationStatus.utcOffset(try #require(TimeZone(secondsFromGMT: 0)), at: Self.now) == "UTC")
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
}
