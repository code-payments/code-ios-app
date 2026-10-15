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
/// Checks the App Store lookup and the repo's release manifest when the app becomes active, at most
/// once per ``UpdatePolicy/checkInterval``, and keeps the last result across launches. Debug,
/// TestFlight and other non-store builds never check, so they never report an update.
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

    private var result: UpdateCheckResult?
    private var lastShownVersion: AppVersion?

    @ObservationIgnored private let installedVersion: AppVersion?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let fetch: @Sendable (URL) async throws -> Data
    @ObservationIgnored private let isStoreBuild: () async -> Bool
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var storeDelegate: StoreProductDelegate?
    @ObservationIgnored private var shownToastID: ToastController.Toast.ID?

    // MARK: - Init -

    init(
        installedVersion: String = AppMeta.version,
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        fetch: @escaping @Sendable (URL) async throws -> Data = UpdateAvailability.fetchFromNetwork,
        isStoreBuild: @escaping () async -> Bool = UpdateAvailability.isRunningStoreBuild
    ) {
        self.installedVersion = AppVersion(installedVersion)
        self.defaults = defaults
        self.now = now
        self.fetch = fetch
        self.isStoreBuild = isStoreBuild
        self.result = Self.load(UpdateCheckResult.self, .updateCheckResult, from: defaults)
        self.lastShownVersion = Self.load(AppVersion.self, .updateToastShownVersion, from: defaults)
        #if DEBUG
        applyDebugOverride()
        #endif
    }

    // MARK: - Check -

    /// Starts a store check unless one ran within ``UpdatePolicy/checkInterval`` or one is under way.
    func refresh() {
        guard refreshTask == nil else { return }
        #if DEBUG
        if Self.debugOverride != nil { return }
        #endif
        if let result, now().timeIntervalSince(result.checkedAt) < UpdatePolicy.checkInterval { return }
        refreshTask = Task {
            await check()
            refreshTask = nil
        }
    }

    /// Runs one store check and records what it found. A failed lookup reads as no update.
    func check() async {
        guard await isStoreBuild() else {
            result = nil
            return
        }
        let checkedAt = now()
        let country = Locale.current.region?.identifier ?? "us"

        async let lookupData = fetch(StoreRelease.lookupURL(country: country))
        async let manifestData = fetch(ReleaseManifest.url)

        let release: StoreRelease?
        do {
            release = StoreRelease.parseLookup(try await lookupData)
        } catch {
            logger.warning("App Store lookup failed", metadata: ["error": "\(error)"])
            release = nil
        }

        var manifest: ReleaseManifest?
        do {
            manifest = ReleaseManifest.parse(try await manifestData)
        } catch {
            logger.warning("Release manifest fetch failed", metadata: ["error": "\(error)"])
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

    /// Whether this build came from the App Store. Debug builds never do; TestFlight reports sandbox and a
    /// build run from Xcode reports `xcode`.
    static func isRunningStoreBuild() async -> Bool {
        #if DEBUG
        return false
        #else
        guard let transaction = try? await AppTransaction.shared.payloadValue else { return false }
        return transaction.environment == .production
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

    private func applyDebugOverride() {
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
