//
//  UpdateAvailability.swift
//  Flipcash
//

import Foundation
import StoreKit
import UIKit
import FlipcashCore
import FlipcashUI

nonisolated private let logger = Logger(label: "flipcash.update-availability")

/// Whether a newer App Store version exists, and whether the one-time "New version available" toast
/// may show for it.
///
/// Checks the App Store lookup and the repo's release manifest when the app becomes active: every time
/// it returns from the background, otherwise at most once per ``UpdatePolicy/checkInterval``. Keeps the last result across launches. Only a store
/// build looks up the store, so debug, TestFlight and other builds never report a store update; every
/// build reads the manifest for the newest TestFlight build.
@MainActor
@Observable
final class UpdateAvailability {

    /// The newer store version, or `nil` when the installed build is current or nothing is known.
    var newerVersion: AppVersion? {
        UpdateEligibility.newerVersion(installed: installedVersion, release: result?.release)
    }

    /// Whether the toast may show now: a newer version is priority or stale, and it hasn't shown yet.
    var isToastEligible: Bool {
        UpdateEligibility.isToastEligible(
            installed: installedVersion,
            result: result,
            lastShownVersion: lastShownVersion,
            now: now()
        )
    }

    /// How the installed build reached the device. Unknown (`other`) until the first check resolves it.
    private(set) var channel: InstallChannel

    /// The newest TestFlight build the manifest names, or `nil` when it hasn't been read.
    private(set) var latestTestFlightBuild: Int?

    /// The build number of the installed app, or `nil` when the bundle's isn't a number.
    @ObservationIgnored let installedBuild: Int?

    private var result: UpdateCheckResult?
    private var lastShownVersion: AppVersion?

    @ObservationIgnored private let installedVersion: AppVersion?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let fetch: @Sendable (URL) async throws -> Data
    @ObservationIgnored private let installChannel: () async -> InstallChannel
    @ObservationIgnored private var lastManifestCheck: Date?
    /// Set while the app is in the background, so the next ``refresh()`` skips the interval.
    @ObservationIgnored private var resumesFromBackground = false
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var storeDelegate: StoreProductDelegate?
    @ObservationIgnored private var shownToastID: ToastController.Toast.ID?

    // MARK: - Init -

    init(
        installedVersion: String = AppMeta.version,
        installedBuild: String = AppMeta.build,
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        fetch: @escaping @Sendable (URL) async throws -> Data = UpdateAvailability.fetchFromNetwork,
        installChannel: @escaping () async -> InstallChannel = UpdateAvailability.resolveInstallChannel
    ) {
        self.installedVersion = AppVersion(installedVersion)
        self.installedBuild = Int(installedBuild)
        self.defaults = defaults
        self.now = now
        self.fetch = fetch
        self.installChannel = installChannel
        self.result = Self.load(UpdateCheckResult.self, .updateCheckResult, from: defaults)
        self.lastShownVersion = Self.load(AppVersion.self, .updateToastShownVersion, from: defaults)
        self.latestTestFlightBuild = Self.load(Int.self, .latestTestFlightBuild, from: defaults)
        self.channel = Self.load(InstallChannel.self, .installChannel, from: defaults) ?? .other
        #if DEBUG
        applyDebugOverride()
        #endif
    }

    // MARK: - Check -

    /// Marks the app as gone to the background, so the check on its return runs whenever the last one did.
    func appDidEnterBackground() {
        resumesFromBackground = true
    }

    /// Starts a store check unless one is under way or, outside a return from the background, one ran
    /// within ``UpdatePolicy/checkInterval``. Returns whether it started one.
    @discardableResult
    func refresh() -> Bool {
        guard refreshTask == nil else { return false }
        #if DEBUG
        if Self.hasDebugOverride { return false }
        #endif
        if !resumesFromBackground,
           let lastCheck = result?.checkedAt ?? lastManifestCheck,
           now().timeIntervalSince(lastCheck) < UpdatePolicy.checkInterval { return false }
        resumesFromBackground = false
        refreshTask = Task {
            await check()
            refreshTask = nil
        }
        return true
    }

    /// Runs one check and records what it found. Every build reads the manifest for the newest TestFlight
    /// build; only a store build looks up the store, and a failed lookup reads as no update.
    func check() async {
        let channel = await installChannel()
        self.channel = channel
        save(channel, .installChannel)
        let checkedAt = now()
        lastManifestCheck = checkedAt

        async let manifestData = fetch(ReleaseManifest.url)
        var manifest: ReleaseManifest?
        do {
            manifest = ReleaseManifest.parse(try await manifestData)
        } catch {
            logger.warning("Release manifest fetch failed", metadata: ["error": "\(error)"])
        }
        if let build = manifest?.testFlightBuild {
            latestTestFlightBuild = build
            save(build, .latestTestFlightBuild)
        }

        guard channel == .store else {
            result = nil
            return
        }

        let country = Locale.current.region?.identifier ?? "us"
        let release: StoreRelease?
        do {
            release = StoreRelease.parseLookup(try await fetch(StoreRelease.lookupURL(country: country)))
        } catch {
            logger.warning("App Store lookup failed", metadata: ["error": "\(error)"])
            release = nil
        }

        guard let release else {
            result = nil
            save(UpdateCheckResult?.none, .updateCheckResult)
            return
        }
        let checked = UpdateCheckResult(
            release: release,
            priority: manifest?.priority(for: release.version) ?? 0,
            checkedAt: checkedAt
        )
        result = checked
        save(checked, .updateCheckResult)
        logger.info("Checked for update", metadata: [
            "storeVersion": "\(release.version)",
            "priority": "\(checked.priority)",
            "isNewer": "\(newerVersion != nil)",
        ])
    }

    // MARK: - Toast -

    /// Shows the update toast on `toasts` if it is eligible, and records its version as seen once it is
    /// on screen. Returns whether it showed.
    @discardableResult
    func showToastIfEligible(on toasts: ToastController, timeout: Duration) -> Bool {
        guard isToastEligible, let version = newerVersion else { return false }
        let toast = ToastController.Toast(
            "New version available",
            messageIdentifier: "update-available-toast",
            action: .init("Update", accessibilityIdentifier: "update-available-toast-action") { [weak self] in
                self?.openStore()
            },
            duration: timeout
        )
        toasts.show(toast)
        // The controller drops a toast while something covers the app; only one that went up counts.
        guard toasts.current?.id == toast.id else { return false }
        lastShownVersion = version
        shownToastID = toast.id
        save(version, .updateToastShownVersion)
        logger.info("Showed update toast", metadata: ["version": "\(version)"])
        return true
    }

    /// Dismisses the update toast from `toasts` if it is still showing. It already counts as seen.
    func dismissToast(on toasts: ToastController) {
        guard let shownToastID else { return }
        toasts.dismiss(shownToastID)
        self.shownToastID = nil
    }

    // MARK: - Store -

    /// Opens the app's App Store page in the app, falling back to the App Store app when the page can't load.
    func openStore() {
        guard let presenter = Self.topViewController else {
            URL.appStoreApplicationHome.openWithApplication()
            return
        }
        let store = SKStoreProductViewController()
        let delegate = StoreProductDelegate { [weak self] in self?.storeDelegate = nil }
        store.delegate = delegate
        storeDelegate = delegate
        presenter.present(store, animated: true)
        store.loadProduct(withParameters: [SKStoreProductParameterITunesItemIdentifier: Self.appStoreID]) { loaded, error in
            guard !loaded else { return }
            Task { @MainActor in
                logger.warning("App Store product failed to load", metadata: ["error": "\(String(describing: error))"])
                store.dismiss(animated: true) {
                    URL.appStoreApplicationHome.openWithApplication()
                }
            }
        }
    }

    /// Opens the app's page in TestFlight, which is where a tester installs the newer build.
    func openTestFlight() {
        UIApplication.shared.open(URL.testFlightApplicationHome, options: [:]) { opened in
            guard !opened else { return }
            logger.warning("TestFlight failed to open")
        }
    }

    private static let appStoreID = 6758636374

    private static var topViewController: UIViewController? {
        var top = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }

    // MARK: - Defaults -

    /// Fetches `url` over the shared session.
    nonisolated static func fetchFromNetwork(_ url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    /// How this build was installed. Debug builds are `other`; TestFlight reports sandbox, the App Store
    /// production, and a build run from Xcode reports `xcode`.
    static func resolveInstallChannel() async -> InstallChannel {
        #if DEBUG
        return .other
        #else
        guard let transaction = try? await AppTransaction.shared.payloadValue else { return .other }
        switch transaction.environment {
        case .production: return .store
        case .sandbox: return .testFlight
        default: return .other
        }
        #endif
    }

    // MARK: - Persistence -

    private static func load<T: Decodable>(_ type: T.Type, _ key: DefaultsKey, from defaults: UserDefaults) -> T? {
        guard let data = defaults.data(forKey: key.rawValue) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func save<T: Encodable>(_ value: T?, _ key: DefaultsKey) {
        guard let value, let data = try? JSONEncoder().encode(value) else {
            defaults.removeObject(forKey: key.rawValue)
            return
        }
        defaults.set(data, forKey: key.rawValue)
    }

    // MARK: - Debug -

    #if DEBUG
    /// The store version a debug launch pretends to find, set by the `-UpdateAvailableOverride <version>`
    /// launch argument. It reads as a priority update and ignores the seen-once record.
    private static var debugOverride: AppVersion? {
        UserDefaults.standard.string(forKey: "UpdateAvailableOverride").flatMap(AppVersion.init)
    }

    /// The channel a debug launch pretends to run on, set by `-InstallChannelOverride store|testFlight`.
    private static var channelOverride: InstallChannel? {
        UserDefaults.standard.string(forKey: "InstallChannelOverride").flatMap(InstallChannel.init)
    }

    /// The newest TestFlight build a debug launch pretends to find, set by `-TestFlightBuildOverride <build>`.
    private static var testFlightBuildOverride: Int? {
        UserDefaults.standard.object(forKey: "TestFlightBuildOverride") as? Int
    }

    private static var hasDebugOverride: Bool {
        debugOverride != nil || channelOverride != nil || testFlightBuildOverride != nil
    }

    private func applyDebugOverride() {
        if let channel = Self.channelOverride { self.channel = channel }
        if let build = Self.testFlightBuildOverride { latestTestFlightBuild = build }
        guard let version = Self.debugOverride else { return }
        result = UpdateCheckResult(
            release: StoreRelease(version: version, releasedAt: now()),
            priority: UpdatePolicy.priorityThreshold,
            checkedAt: now()
        )
        lastShownVersion = nil
    }
    #endif
}

/// Clears the presenter's hold on the store sheet once the user closes it.
private final class StoreProductDelegate: NSObject, SKStoreProductViewControllerDelegate {
    private let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    func productViewControllerDidFinish(_ viewController: SKStoreProductViewController) {
        viewController.dismiss(animated: true)
        onFinish()
    }
}
