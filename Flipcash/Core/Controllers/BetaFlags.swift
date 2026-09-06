//
//  BetaFlags.swift
//  Code
//
//  Created by Dima Bart on 2021-03-25.
//

import Foundation
import SwiftUI

/// Manages feature flags gated behind the beta access menu in Settings.
///
/// Access is unlocked by tapping the app version 9 times, which reveals the
/// "Beta Features" row. Each ``Option`` is persisted to `UserDefaults` via
/// `@Defaults` and survives app relaunches. An option marked
/// ``Option/isOnByDefault`` starts on, once, for a user who has never chosen.
///
/// Read flags from anywhere with `BetaFlags.shared.hasEnabled(.vibrateOnScan)`.
/// In SwiftUI views, inject via `@Environment(BetaFlags.self)`.
@Observable
class BetaFlags {

    static let shared = BetaFlags()
    private(set) var options: Set<Option> = []
    private(set) var accessGranted: Bool = false
    
    // Stored as raw strings, not as `Option`: decoding a `Set<Option>` fails
    // whole when it holds a case that has since been removed, silently resetting
    // every other flag with it.
    @ObservationIgnored @Defaults(.betaFlags) private var storedOptions: Set<String>?
    @ObservationIgnored @SecureString(.betaFlagsEnabled) private var storedAccessGranted: String?

    // The options whose `isOnByDefault` has already been applied. Kept apart
    // from `storedOptions` so that "never offered" and "turned off" stay
    // distinguishable: without it a default-on flag would switch itself back on
    // at every launch.
    @ObservationIgnored @Defaults(.appliedBetaFlagDefaults) private var appliedDefaults: Set<String>?
    
    // MARK: - Init -
    
    private init() {
        readStoredOptions()
        applyDefaults()
        readAccessGranted()
    }
    
    /// Returns `true` when the given beta flag is currently active.
    ///
    /// A `.shipped` option reports on for everyone regardless of what is stored,
    /// so a rollout needs no call-site edits and no user can opt back out.
    func hasEnabled(_ option: Option) -> Bool {
        if option.availability == .shipped { return true }
        return options.contains(option)
    }
    
    /// Whether the Beta Features screen has anything to show — the public
    /// flags everyone gets, plus the developer-only section once the version
    /// easter egg unlocks access. False means the screen draws its empty state.
    var hasVisibleOptions: Bool {
        accessGranted || Option.allCases.contains { $0.availability == .publicBeta }
    }

    /// Enables or disables a beta flag and persists the change to disk.
    func set(_ option: Option, enabled: Bool) {
        if enabled {
            options.insert(option)
        } else {
            options.remove(option)
        }
        writeToCache()
    }
    
    /// Resets every flag, then enables each option named in the
    /// `--beta-flags=<comma-separated rawValues>` launch argument.
    func applyLaunchArgumentOverrides() {
        let prefix = "--beta-flags="
        let enabled = CommandLine.arguments
            .first { $0.hasPrefix(prefix) }?
            .dropFirst(prefix.count)
            .split(separator: ",")
            .compactMap { Option(rawValue: String($0)) }

        options = Set(enabled ?? [])
        writeToCache()
    }

    /// Toggles whether the beta features section is visible in Settings.
    /// Controlled by the 9-tap easter egg on the app version label.
    func setAccessGranted(_ granted: Bool) {
        if granted {
            storedAccessGranted = "granted"
        } else {
            storedAccessGranted = nil
        }
        accessGranted = granted
    }
    
    /// Creates a two-way `Binding` for use in SwiftUI toggle controls.
    func bindingFor(option: Option) -> Binding<Bool> {
        Binding { [weak self] in
            self?.options.contains(option) ?? false
            
        } set: { [weak self] enabled in
            self?.set(option, enabled: enabled)
        }
    }
    
    /// Turns on each default-on option the user has not been offered yet, and
    /// records the offer.
    ///
    /// Runs per option rather than once overall, so a flag added in a later
    /// release still starts on for a user who already has flags stored.
    private func applyDefaults() {
        var applied = appliedDefaults ?? []
        let pending = Option.allCases.filter { $0.isOnByDefault && !applied.contains($0.rawValue) }
        guard !pending.isEmpty else { return }

        for option in pending {
            options.insert(option)
            applied.insert(option.rawValue)
        }

        appliedDefaults = applied
        writeToCache()
    }

    // MARK: - Cache -
    
    private func writeToCache() {
        self.storedOptions = Set(options.map(\.rawValue))
    }
    
    private func readAccessGranted() {
        if let _ = storedAccessGranted {
            accessGranted = true
        } else {
            accessGranted = false
        }
    }
    
    private func readStoredOptions() {
        if let stored = storedOptions {
            self.options = Set(stored.compactMap(Option.init(rawValue:)))
        }
    }
}

// MARK: - Option -

extension BetaFlags {
    enum Option: String, Hashable, Equatable, Codable, CaseIterable, Identifiable {

        case vibrateOnScan
        case enableCoinbase
        case walletDepositArrival
        case glassReplyQuote

        var id: String {
            localizedTitle
        }

        var localizedTitle: String {
            switch self {
            case .vibrateOnScan:
                return "Vibrate on scan"
            case .enableCoinbase:
                return "Enable Coinbase"
            case .walletDepositArrival:
                return "Show deposits arriving in the wallet"
            case .glassReplyQuote:
                return "Glass reply quote"
            }
        }

        var localizedDescription: String {
            switch self {
            case .vibrateOnScan:
                return "If enabled, the device will vibrate to indicate that the camera has registered the code on the bill"
            case .enableCoinbase:
                return "If enabled, Coinbase onramp will be available regardless of region"
            case .walletDepositArrival:
                return "If enabled, Put in Wallet opens the wallet and shows the balance rising and any new card arriving. If disabled, the bill is dismissed where it stands"
            case .glassReplyQuote:
                return "If enabled, the quote above the composer is a floating Liquid Glass capsule. If disabled, it is an inset panel on the bar's own surface"
            }
        }

        /// Which Settings surface exposes this flag's toggle.
        var availability: Availability {
            switch self {
            case .vibrateOnScan:        return .developer
            case .enableCoinbase:       return .developer
            case .walletDepositArrival: return .developer
            case .glassReplyQuote:      return .developer
            }
        }

        /// Whether the flag starts on for a user who has never chosen — a feature
        /// that ships on but keeps its off switch while it settles.
        var isOnByDefault: Bool {
            switch self {
            case .vibrateOnScan:        return false
            case .enableCoinbase:       return false
            case .walletDepositArrival: return true
            case .glassReplyQuote:      return false
            }
        }
    }

    /// Where a beta flag's toggle appears in Settings.
    enum Availability {
        /// The hidden developer "Beta Flags" screen, unlocked by the 9-tap easter egg.
        case developer
        /// The public "Advanced ▸ Beta Features" screen, visible to every user.
        case publicBeta
        /// Shipped to everyone: forced on by ``BetaFlags/hasEnabled(_:)`` and
        /// listed nowhere, since there is no longer a choice to offer. The case
        /// stays until its branches are torn out of the call sites.
        case shipped
    }
}

extension BetaFlags {
    static let mock = BetaFlags()
}
