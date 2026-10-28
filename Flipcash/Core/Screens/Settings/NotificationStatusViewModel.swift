//
//  NotificationStatusViewModel.swift
//  Flipcash
//

import UIKit
import FlipcashCore
import UserNotifications

/// Runs the notification status page's checks and holds what the page shows. The rules live in
/// ``NotificationStatus``; this type gathers the inputs and acts on the fixes.
@Observable
final class NotificationStatusViewModel {

    private(set) var snapshot: NotificationStatus.Snapshot?
    private(set) var registration: NotificationStatus.Registration = .checking
    /// Whether the folded "N checks passed" row has been opened. Lasts until the page closes.
    var isExpanded = false
    /// Whether a test notification was scheduled since the page opened.
    private(set) var isTestSent = false

    @ObservationIgnored private let pushController: PushController
    @ObservationIgnored private var registrationTask: Task<Void, Never>?

    init(pushController: PushController) {
        self.pushController = pushController
    }

    /// `nil` until the phone's settings have been read once.
    var page: NotificationStatus.Page? {
        snapshot.map {
            NotificationStatus.evaluate(
                snapshot: $0,
                registration: registration,
                saved: pushController.savedRegistration,
                now: .now
            )
        }
    }

    var report: String {
        NotificationStatus.report(
            snapshot: snapshot ?? .init(authorization: .notDetermined),
            registration: registration,
            saved: pushController.savedRegistration,
            context: .init(
                appVersion: Self.appVersion,
                osVersion: UIDevice.current.systemVersion,
                deviceModel: Self.deviceModel,
                tokenSuffix: pushController.tokenSuffix,
                lastAPNsError: pushController.lastAPNsError
            ),
            now: .now
        )
    }

    // MARK: - Checks -

    /// Reads the phone's settings and re-registers, unless a registration is already running.
    func runChecks() async {
        await refreshSettings()
        if registrationTask == nil {
            register()
        }
    }

    /// Marks an unfinished registration as interrupted when the page goes away.
    func stop() {
        guard let registrationTask else { return }
        registrationTask.cancel()
        self.registrationTask = nil
        registration = .interrupted
    }

    private func refreshSettings() async {
        let settings = await PushController.fetchStatus()
        snapshot = NotificationStatus.Snapshot(settings)
    }

    private func register(deletingToken: Bool = false) {
        registrationTask?.cancel()
        registration = .checking
        registrationTask = Task { [pushController] in
            let result = await pushController.checkRegistration(deletingToken: deletingToken)
            guard !Task.isCancelled else { return }
            registration = result
            registrationTask = nil
        }
    }

    // MARK: - Actions -

    func perform(_ fix: NotificationStatus.Fix) async {
        switch fix {
        case .openNotificationSettings:
            guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
            await UIApplication.shared.open(url)
        case .requestAuthorization:
            do {
                try await PushController.authorizeAndRegister()
            } catch {
                ErrorReporting.captureError(error, reason: "Failed to request notification authorization")
            }
            await runChecks()
        case .retryRegistration:
            register()
        case .retryRegistrationDeletingToken:
            register(deletingToken: true)
        }
    }

    /// Re-reads the permission first: if it went away while the page was open, nothing is sent
    /// and the page shows notifications as off.
    func sendTest() async {
        await refreshSettings()
        guard page?.isTestEnabled == true else { return }

        do {
            try await pushController.scheduleTestNotification()
            isTestSent = true
        } catch {
            ErrorReporting.captureError(error, reason: "Failed to schedule test notification")
        }
    }

    // MARK: - Device -

    private static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    /// The hardware identifier, such as "iPhone17,1". The simulator reports the device it emulates.
    private static var deviceModel: String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return simulated
        }
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}

// MARK: - Snapshot -

extension NotificationStatus.Snapshot {

    init(_ settings: UNNotificationSettings) {
        self.init(
            authorization: .init(settings.authorizationStatus),
            alert: .init(settings.alertSetting),
            lockScreen: .init(settings.lockScreenSetting),
            sound: .init(settings.soundSetting),
            badge: .init(settings.badgeSetting),
            alertStyle: .init(settings.alertStyle)
        )
    }
}

private extension NotificationStatus.Snapshot.Authorization {
    init(_ status: UNAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .notDetermined
        case .denied:        self = .denied
        case .authorized:    self = .authorized
        case .provisional:   self = .provisional
        case .ephemeral:     self = .ephemeral
        @unknown default:    self = .authorized
        }
    }
}

private extension NotificationStatus.Snapshot.Setting {
    init(_ setting: UNNotificationSetting) {
        switch setting {
        case .enabled:      self = .enabled
        case .disabled:     self = .disabled
        case .notSupported: self = .notSupported
        @unknown default:   self = .notSupported
        }
    }
}

private extension NotificationStatus.Snapshot.AlertStyle {
    init(_ style: UNAlertStyle) {
        switch style {
        case .none:       self = .none
        case .banner:     self = .banner
        case .alert:      self = .alert
        @unknown default: self = .banner
        }
    }
}
