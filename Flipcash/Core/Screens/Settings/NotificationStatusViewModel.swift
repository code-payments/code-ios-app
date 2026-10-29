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
    /// Whether the folded "N checks passed" row is open. Lasts until the page closes or the user
    /// folds it again.
    var isExpanded = false
    /// Whether Flipcash accepted a test notification since the page opened.
    private(set) var isTestSent = false
    /// Whether a `SendTestPush` call is in flight, during which the test button is disabled.
    private(set) var isSendingTest = false
    /// The page as it stood when "Check Again" was tapped, shown with every row Checking until
    /// that run ends.
    private var recheckingFrom: NotificationStatus.Page?
    /// The saved `AddToken` record as it stood when the current registration started, before
    /// that attempt overwrote it.
    private var savedBeforeRegistration: NotificationStatus.RegistrationRecord?
    /// Whether a run has finished since the page opened, after which the summary keeps
    /// "Checked just now" through every later run.
    private var hasChecked = false

    @ObservationIgnored private let pushController: PushController
    @ObservationIgnored private let readSettings: () async -> NotificationStatus.Snapshot
    @ObservationIgnored private let registrationCheck: (_ deletingToken: Bool) async -> NotificationStatus.Registration
    @ObservationIgnored private let savedRegistration: () -> NotificationStatus.RegistrationRecord?
    @ObservationIgnored private let requestAuthorization: () async throws -> Bool
    @ObservationIgnored private let sendTestPush: () async -> NotificationStatus.TestResult
    @ObservationIgnored private let recheckPause: Duration
    @ObservationIgnored private var registrationTask: Task<Void, Never>?

    /// `readSettings`, `registrationCheck`, `savedRegistration`, `requestAuthorization` and
    /// `sendTestPush` default to the phone's settings, ``PushController/checkRegistration(deletingToken:)``,
    /// ``PushController/savedRegistration``, ``PushController/authorizeAndRegister()`` and
    /// ``PushController/sendTestPush()``.
    /// `recheckPause` is the least time "Check Again" shows the rows as Checking, so a fast
    /// re-check still reads as one.
    init(
        pushController: PushController,
        readSettings: (() async -> NotificationStatus.Snapshot)? = nil,
        registrationCheck: ((_ deletingToken: Bool) async -> NotificationStatus.Registration)? = nil,
        savedRegistration: (() -> NotificationStatus.RegistrationRecord?)? = nil,
        requestAuthorization: (() async throws -> Bool)? = nil,
        sendTestPush: (() async -> NotificationStatus.TestResult)? = nil,
        recheckPause: Duration = .milliseconds(500)
    ) {
        self.pushController = pushController
        self.readSettings = readSettings ?? { NotificationStatus.Snapshot(await PushController.fetchStatus()) }
        self.registrationCheck = registrationCheck ?? { [pushController] in
            await pushController.checkRegistration(deletingToken: $0)
        }
        self.savedRegistration = savedRegistration ?? { [pushController] in pushController.savedRegistration }
        self.requestAuthorization = requestAuthorization ?? { try await PushController.authorizeAndRegister() }
        self.sendTestPush = sendTestPush ?? { [pushController] in await pushController.sendTestPush() }
        self.recheckPause = recheckPause
    }

    /// `nil` until the phone's settings have been read once.
    var page: NotificationStatus.Page? {
        if let recheckingFrom {
            return recheckingFrom.rechecking
        }
        return snapshot.map {
            NotificationStatus.evaluate(
                snapshot: $0,
                registration: registration,
                saved: savedBeforeRegistration,
                hasChecked: hasChecked,
                now: .now
            )
        }
    }

    /// Whether a run is in progress, during which "Check Again" is disabled.
    var isRunning: Bool {
        recheckingFrom != nil || registration == .checking
    }

    var report: String {
        NotificationStatus.report(
            snapshot: snapshot ?? .init(authorization: .notDetermined),
            registration: registration,
            saved: savedRegistration(),
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

    /// Re-runs every check, including a fresh `AddToken`, keeping the rows the page shows now.
    /// After a rejected push token it deletes the local token first, as "Try Again" does.
    /// Returns once the run has finished; does nothing while a run is already in progress.
    func checkAgain() async {
        guard !isRunning, let page else { return }
        recheckingFrom = page
        register(deletingToken: registration == .finished(.invalidPushToken))
        async let pause: Void? = try? Task.sleep(for: recheckPause)
        await refreshSettings()
        await registrationTask?.value
        _ = await pause
        recheckingFrom = nil
    }

    /// Re-reads only the phone's settings, for a return to the foreground. Registration keeps its
    /// last result, so a folded page doesn't unfold and refold.
    func rereadSettings() async {
        await refreshSettings()
    }

    /// Drops an unfinished registration when the page goes away; the cancelled attempt saves
    /// nothing.
    func stop() {
        registrationTask?.cancel()
        registrationTask = nil
    }

    private func refreshSettings() async {
        snapshot = await readSettings()
    }

    private func register(deletingToken: Bool = false) {
        registrationTask?.cancel()
        savedBeforeRegistration = savedRegistration()
        registration = .checking
        registrationTask = Task { [registrationCheck] in
            let result = await registrationCheck(deletingToken)
            guard !Task.isCancelled else { return }
            registration = result
            hasChecked = true
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
            var granted = false
            do {
                granted = try await requestAuthorization()
            } catch {
                ErrorReporting.captureError(error, reason: "Failed to request notification authorization")
            }
            await refreshSettings()
            // The phone can only register once notifications are allowed.
            if granted {
                register()
            }
        case .retryRegistration:
            register()
        case .retryRegistrationDeletingToken:
            register(deletingToken: true)
        }
    }

    /// Re-reads the permission first: if it went away while the page was open, nothing is sent
    /// and the page shows notifications as off. Returns how the send went, or `nil` when nothing
    /// was sent.
    @discardableResult
    func sendTest() async -> NotificationStatus.TestResult? {
        guard !isSendingTest else { return nil }
        isSendingTest = true
        defer { isSendingTest = false }

        await refreshSettings()
        guard page?.isTestEnabled == true else { return nil }

        let result = await sendTestPush()
        if result == .sent {
            isTestSent = true
        }
        return result
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
