//
//  NotificationStatus.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// The Settings › Advanced › Notifications page, as a pure function from what the phone reports
/// and how the last push registration went to the rows, summary and report the page shows.
///
/// Free of `UserNotifications` and UIKit types so the same rules can move to shared code later;
/// the app maps `UNNotificationSettings` into ``Snapshot`` at the edge.
public enum NotificationStatus {

    /// Marks the local test notification in its `userInfo`, so the notification delegate can
    /// recognise it before trying to decode a push payload it doesn't carry.
    public static let testUserInfoKey = "flipcash_test"

    /// Groups the test notification in Notification Center.
    public static let testThreadIdentifier = "notification-test"

    /// Seconds between the tap and the test notification.
    public static let testDelay: TimeInterval = 3

    /// How long a registration may take before it counts as unreachable.
    public static let registrationTimeout: Duration = .seconds(10)

    /// Whether `userInfo` belongs to the local test notification.
    public static func isTestNotification(_ userInfo: [AnyHashable: Any]) -> Bool {
        userInfo[testUserInfoKey] as? Bool == true
    }
}

// MARK: - Input -

extension NotificationStatus {

    /// The phone's notification settings for this app, mirroring `UNNotificationSettings`.
    public struct Snapshot: Equatable, Sendable {

        public enum Authorization: String, Sendable {
            case notDetermined
            case denied
            case authorized
            case provisional
            case ephemeral
        }

        public enum Setting: String, Sendable {
            case enabled
            case disabled
            /// The device can't have this setting; it is never treated as off.
            case notSupported

            var isOff: Bool {
                switch self {
                case .disabled:               true
                case .enabled, .notSupported: false
                }
            }
        }

        public enum AlertStyle: String, Sendable {
            case none
            case banner
            case alert
        }

        public var authorization: Authorization
        public var alert: Setting
        public var lockScreen: Setting
        public var sound: Setting
        public var badge: Setting
        public var alertStyle: AlertStyle

        public init(
            authorization: Authorization,
            alert: Setting = .enabled,
            lockScreen: Setting = .enabled,
            sound: Setting = .enabled,
            badge: Setting = .enabled,
            alertStyle: AlertStyle = .banner
        ) {
            self.authorization = authorization
            self.alert = alert
            self.lockScreen = lockScreen
            self.sound = sound
            self.badge = badge
            self.alertStyle = alertStyle
        }
    }

    /// How an `AddToken` call ended. Persisted, so the raw values are stable.
    public enum RegistrationResult: String, Codable, Sendable {
        case ok
        case invalidPushToken
        case transport
        case unknown

        /// Classifies a failed `AddToken` call. A dropped or cancelled call couldn't reach
        /// Flipcash; anything else the server didn't accept is unknown.
        public init(_ error: ErrorAddToken) {
            switch error {
            case .invalidPushToken:             self = .invalidPushToken
            case .transportFailure, .cancelled: self = .transport
            case .ok, .unknown, .rejected:      self = .unknown
            }
        }
    }

    /// Which path made an `AddToken` call. Persisted, so the raw values are stable.
    public enum RegistrationSource: String, Codable, Sendable {
        case login
        case refresh
        case statusPage
    }

    /// The last `AddToken` outcome from any call site, saved per account.
    public struct RegistrationRecord: Codable, Equatable, Sendable {
        public var at: Date
        public var result: RegistrationResult
        public var source: RegistrationSource
        /// When an `AddToken` call from any call site last returned `ok`. Only a newer `ok`
        /// replaces it, so a later failure keeps it.
        public var lastRegistrationOkAt: Date?

        public init(at: Date, result: RegistrationResult, source: RegistrationSource, lastRegistrationOkAt: Date? = nil) {
            self.at = at
            self.result = result
            self.source = source
            self.lastRegistrationOkAt = lastRegistrationOkAt
        }

        /// The record for a new outcome at `at`, carrying forward the last `ok` time from `previous`.
        public static func recording(
            _ result: RegistrationResult,
            source: RegistrationSource,
            at: Date,
            after previous: RegistrationRecord?
        ) -> RegistrationRecord {
            let okAt: Date? = switch result {
            case .ok:                                     at
            case .invalidPushToken, .transport, .unknown: previous?.lastRegistrationOkAt
            }
            return RegistrationRecord(at: at, result: result, source: source, lastRegistrationOkAt: okAt)
        }
    }

    /// Where the page's own registration check stands.
    public enum Registration: Equatable, Sendable {
        /// The check is running.
        case checking
        /// Firebase had no token to give, because the phone has no APNs token.
        case noAPNsToken
        /// `AddToken` answered, or timed out.
        case finished(RegistrationResult)
    }
}

// MARK: - Output -

extension NotificationStatus {

    public enum Status: String, Sendable {
        case pass
        case warning
        case fail
        case checking
    }

    public enum Check: String, CaseIterable, Sendable {
        /// i1
        case permission
        /// i2
        case display
        /// i3
        case soundsAndBadges
        /// i4
        case registration

        /// The check's name, used in the report and the passing row.
        public var name: String {
            switch self {
            case .permission:      "Notifications allowed"
            case .display:         "Banners and Lock Screen"
            case .soundsAndBadges: "Sounds and badges"
            case .registration:    "Registered for push"
            }
        }

        public var group: Group {
            switch self {
            case .permission, .display, .soundsAndBadges: .phone
            case .registration:                           .flipcash
            }
        }
    }

    public enum Group: String, CaseIterable, Sendable {
        case phone
        case flipcash

        public var title: String {
            switch self {
            case .phone:    "On This Phone"
            case .flipcash: "With Flipcash"
            }
        }
    }

    /// What a row's trailing button does.
    public enum Fix: Equatable, Sendable {
        /// Opens this app's notification settings in the Settings app.
        case openNotificationSettings
        /// Shows the system permission prompt in the app.
        case requestAuthorization
        /// Runs the registration again.
        case retryRegistration
        /// Deletes the local push token, then runs the registration again.
        case retryRegistrationDeletingToken
    }

    public struct Row: Equatable, Identifiable, Sendable {
        public var check: Check
        public var status: Status
        public var title: String
        public var detail: String?
        public var fix: Fix?
        /// The raw value behind the status, for the report.
        public var raw: String?

        public var id: Check { check }

        /// The label on the fix button. The permission row says "Turn On" whether it opens
        /// Settings or asks in the app.
        public var fixTitle: String? {
            guard let fix else { return nil }
            if check == .permission { return "Turn On" }
            switch fix {
            case .openNotificationSettings, .requestAuthorization:
                return "Fix"
            case .retryRegistration, .retryRegistrationDeletingToken:
                return "Try Again"
            }
        }
    }

    public struct Summary: Equatable, Sendable {
        public var status: Status
        public var title: String
        public var detail: String?
    }

    public struct Page: Equatable, Sendable {
        /// Visible rows in check order. Rows that don't apply are already left out.
        public var rows: [Row]
        public var summary: Summary
        /// Whether "Send Test Notification" can be tapped.
        public var isTestEnabled: Bool
        /// The title of the row that folds both groups when every check passes.
        public var foldedTitle: String?
        /// The mark on the folded row: Pass, or Checking while the checks run again.
        public var foldedStatus: Status {
            switch summary.status {
            case .checking:              .checking
            case .pass, .warning, .fail: .pass
            }
        }

        public func rows(in group: Group) -> [Row] {
            rows.filter { $0.check.group == group }
        }

        /// This page while its checks run again: the same rows with the same text, each marked
        /// Checking, so nothing on the page moves until the new results land. The summary keeps
        /// its second line from the last finished run.
        public var rechecking: Page {
            var page = self
            for index in page.rows.indices {
                page.rows[index].status = .checking
            }
            page.summary = Summary(status: .checking, title: "Checking…", detail: summary.detail)
            return page
        }
    }
}

// MARK: - Evaluate -

extension NotificationStatus {

    /// What the page shows before the phone's settings have been read: every check, still running.
    public static func checkingPage() -> Page {
        Page(
            rows: Check.allCases.map { check in
                switch check {
                case .permission, .display, .soundsAndBadges:
                    Row(check: check, status: .checking, title: check.name, raw: "checking")
                case .registration:
                    registrationRow(.checking, saved: nil, now: .distantPast, locale: .current)
                }
            },
            summary: Summary(status: .checking, title: "Checking…"),
            isTestEnabled: false
        )
    }

    /// Builds the page from the phone's settings and the registration check.
    ///
    /// `saved` is the `AddToken` record as it stood before this registration attempt started;
    /// a past `ok` in it softens a transport failure into a warning, since the server most likely
    /// still holds a good registration. `hasChecked` is whether a run on this page has finished
    /// before, which keeps the summary's "Checked just now" up while a later run is in progress.
    public static func evaluate(
        snapshot: Snapshot,
        registration: Registration,
        saved: RegistrationRecord?,
        hasChecked: Bool = false,
        now: Date,
        locale: Locale = .current
    ) -> Page {
        let permission = permissionRow(snapshot)
        let permissionFails = permission.status == .fail

        var rows = [permission]
        if !permissionFails {
            rows.append(displayRow(snapshot))
            rows.append(soundsAndBadgesRow(snapshot))
        }
        rows.append(registrationRow(registration, saved: saved, now: now, locale: locale))

        let allPass = rows.allSatisfy { $0.status == .pass }

        return Page(
            rows: rows,
            summary: summary(rows, hasChecked: hasChecked),
            isTestEnabled: !permissionFails,
            foldedTitle: allPass ? plural(rows.count, "check passed", "checks passed") : nil
        )
    }

    static func permissionRow(_ snapshot: Snapshot) -> Row {
        let raw = snapshot.authorization.rawValue
        switch snapshot.authorization {
        case .authorized, .provisional, .ephemeral:
            return Row(check: .permission, status: .pass, title: Check.permission.name, detail: "Allowed in iOS Settings", raw: raw)
        case .denied:
            return Row(check: .permission, status: .fail, title: "Notifications are turned off", detail: "Turned off for Flipcash in iOS Settings", fix: .openNotificationSettings, raw: raw)
        case .notDetermined:
            return Row(check: .permission, status: .fail, title: "Notifications aren't turned on yet", detail: "Flipcash hasn't asked yet", fix: .requestAuthorization, raw: raw)
        }
    }

    static func displayRow(_ snapshot: Snapshot) -> Row {
        let bannersOff = snapshot.alert.isOff || snapshot.alertStyle == .none
        let lockScreenOff = snapshot.lockScreen.isOff

        var off: [String] = []
        if snapshot.alert.isOff { off.append("alert disabled") }
        if snapshot.alertStyle == .none { off.append("alertStyle none") }
        if lockScreenOff { off.append("lockScreen disabled") }
        let raw = off.isEmpty ? nil : off.joined(separator: ", ")

        if bannersOff {
            return Row(check: .display, status: .warning, title: "Banners are off", detail: "New notifications only go to Notification Center", fix: .openNotificationSettings, raw: raw)
        }
        if lockScreenOff {
            return Row(check: .display, status: .warning, title: "Hidden on the Lock Screen", fix: .openNotificationSettings, raw: raw)
        }
        return Row(check: .display, status: .pass, title: Check.display.name, detail: "Both on", raw: raw)
    }

    static func soundsAndBadgesRow(_ snapshot: Snapshot) -> Row {
        let title: String? = switch (snapshot.sound.isOff, snapshot.badge.isOff) {
        case (true, true):   "Sounds and badges are off"
        case (true, false):  "Sounds are off"
        case (false, true):  "Badges are off"
        case (false, false): nil
        }

        var off: [String] = []
        if snapshot.sound.isOff { off.append("sound disabled") }
        if snapshot.badge.isOff { off.append("badge disabled") }
        let raw = off.isEmpty ? nil : off.joined(separator: ", ")

        guard let title else {
            return Row(check: .soundsAndBadges, status: .pass, title: Check.soundsAndBadges.name, detail: "Both on", raw: raw)
        }
        return Row(check: .soundsAndBadges, status: .warning, title: title, fix: .openNotificationSettings, raw: raw)
    }

    static func registrationRow(_ registration: Registration, saved: RegistrationRecord?, now: Date, locale: Locale) -> Row {
        let name = Check.registration.name
        switch registration {
        case .checking:
            return Row(check: .registration, status: .checking, title: "Checking registration…", detail: "Contacting Flipcash", raw: "checking")
        case .noAPNsToken:
            return Row(check: .registration, status: .fail, title: "This phone isn't registered with Apple", fix: .retryRegistration, raw: "noAPNsToken")
        case .finished(.ok):
            return Row(check: .registration, status: .pass, title: name, detail: "Confirmed just now", raw: RegistrationResult.ok.rawValue)
        case .finished(.invalidPushToken):
            return Row(check: .registration, status: .fail, title: "Flipcash rejected this phone's push token", fix: .retryRegistrationDeletingToken, raw: RegistrationResult.invalidPushToken.rawValue)
        case .finished(.transport):
            let raw = RegistrationResult.transport.rawValue
            if let okAt = saved?.lastRegistrationOkAt {
                return Row(check: .registration, status: .warning, title: "Couldn't reach Flipcash", detail: "Last confirmed \(relative(okAt, to: now, locale: locale))", fix: .retryRegistration, raw: raw)
            }
            return Row(check: .registration, status: .fail, title: "Couldn't reach Flipcash", detail: "Check your connection", fix: .retryRegistration, raw: raw)
        case .finished(.unknown):
            return Row(check: .registration, status: .fail, title: "Registration failed", fix: .retryRegistration, raw: RegistrationResult.unknown.rawValue)
        }
    }

    static func summary(_ rows: [Row], hasChecked: Bool) -> Summary {
        let fails = rows.filter { $0.status == .fail }
        let warnings = rows.filter { $0.status == .warning }
        // The second line waits for the first run to finish, then stays through later runs.
        let isChecking = rows.contains { $0.status == .checking }
        let checked = hasChecked || !isChecking ? "Checked just now" : nil

        if !fails.isEmpty {
            let title = fails.contains { $0.check == .permission }
                ? "Notifications are off"
                : plural(fails.count, "thing to fix", "things to fix")
            return Summary(status: .fail, title: title, detail: checked)
        }
        if !warnings.isEmpty {
            return Summary(status: .warning, title: plural(warnings.count, "thing to check", "things to check"), detail: checked)
        }
        if isChecking {
            return Summary(status: .checking, title: "Checking…", detail: checked)
        }
        return Summary(status: .pass, title: "Notifications are working", detail: checked)
    }

    static func plural(_ count: Int, _ one: String, _ many: String) -> String {
        "\(count) \(count == 1 ? one : many)"
    }

    /// Under a minute reads "just now"; the formatter would say "0 minutes ago".
    static func relative(_ date: Date, to now: Date, locale: Locale) -> String {
        guard abs(now.timeIntervalSince(date)) >= 60 else { return "just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }
}

// MARK: - Report -

extension NotificationStatus {

    /// What the report says about the device and app, beyond the checks themselves.
    public struct ReportContext: Sendable {
        public var appVersion: String
        public var osVersion: String
        public var deviceModel: String
        /// The last six characters of the token sent in the latest attempt, or `nil` when that
        /// attempt fetched none.
        public var tokenSuffix: String?
        /// The last `didFailToRegisterForRemoteNotifications` error, if any.
        public var lastAPNsError: String?

        public init(appVersion: String, osVersion: String, deviceModel: String, tokenSuffix: String?, lastAPNsError: String?) {
            self.appVersion = appVersion
            self.osVersion = osVersion
            self.deviceModel = deviceModel
            self.tokenSuffix = tokenSuffix
            self.lastAPNsError = lastAPNsError
        }
    }

    /// The plain-text report for support. Lists every check, including the ones the page hides,
    /// with the raw value behind each status. Never includes the full token or any account id.
    public static func report(
        snapshot: Snapshot,
        registration: Registration,
        saved: RegistrationRecord?,
        context: ReportContext,
        now: Date,
        timeZone: TimeZone = .current
    ) -> String {
        let rows = [
            permissionRow(snapshot),
            displayRow(snapshot),
            soundsAndBadgesRow(snapshot),
            registrationRow(registration, saved: saved, now: now, locale: Locale(identifier: "en_US_POSIX")),
        ]

        var lines = [
            "Flipcash notification report",
            "\(timestamp(now, timeZone: timeZone)) (\(utcOffset(timeZone, at: now)))",
            "App \(context.appVersion) · iOS \(context.osVersion) · \(context.deviceModel)",
            "",
        ]

        for row in rows {
            var raw = row.raw
            if row.check == .registration {
                switch registration {
                case .checking:
                    raw = nil
                case .noAPNsToken:
                    // This run saved nothing, so the record is from an older attempt.
                    break
                case .finished(let result):
                    // `<result>, <source>, <time>`, with an `ok` result left out.
                    if let saved, saved.result == result {
                        raw = [
                            result == .ok ? nil : result.rawValue,
                            saved.source.rawValue,
                            timestamp(saved.at, timeZone: timeZone),
                        ].compactMap { $0 }.joined(separator: ", ")
                    }
                }
            }
            let value = raw.map { " (\($0))" } ?? ""
            lines.append("\(row.check.name): \(row.status.rawValue)\(value)")
            if row.check == .registration {
                lines.append("Last ok: \(saved?.lastRegistrationOkAt.map { timestamp($0, timeZone: timeZone) } ?? "never")")
            }
        }

        lines.append("")
        lines.append("Token: \(context.tokenSuffix.map { "…\($0) (last 6)" } ?? "none")")
        lines.append("Last APNs error: \(context.lastAPNsError ?? "none")")

        return lines.joined(separator: "\n")
    }

    static func timestamp(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    static func utcOffset(_ timeZone: TimeZone, at date: Date) -> String {
        let seconds = timeZone.secondsFromGMT(for: date)
        let sign = seconds < 0 ? "-" : "+"
        let hours = abs(seconds) / 3600
        let minutes = abs(seconds) % 3600 / 60
        return minutes == 0 ? "UTC\(sign)\(hours)" : "UTC\(sign)\(hours):\(String(format: "%02d", minutes))"
    }
}
