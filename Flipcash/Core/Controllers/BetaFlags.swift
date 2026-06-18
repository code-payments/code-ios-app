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
/// `@Defaults` and survives app relaunches.
///
/// Read flags from anywhere with `BetaFlags.shared.hasEnabled(.vibrateOnScan)`.
/// In SwiftUI views, inject via `@Environment(BetaFlags.self)`.
@Observable
class BetaFlags {

    static let shared = BetaFlags()
    private(set) var options: Set<Option> = []
    private(set) var accessGranted: Bool = false
    
    @ObservationIgnored @Defaults(.betaFlags) private var storedOptions: Set<Option>?
    @ObservationIgnored @SecureString(.betaFlagsEnabled) private var storedAccessGranted: String?
    
    // MARK: - Init -
    
    private init() {
        readStoredOptions()
        readAccessGranted()
    }
    
    /// Returns `true` when the given beta flag is currently active.
    func hasEnabled(_ option: Option) -> Bool {
        options.contains(option)
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
    
    // MARK: - Cache -
    
    private func writeToCache() {
        self.storedOptions = options
    }
    
    private func readAccessGranted() {
        if let _ = storedAccessGranted {
            accessGranted = true
        } else {
            accessGranted = false
        }
    }
    
    private func readStoredOptions() {
        if let options = storedOptions {
            self.options = options
        }
    }
}

// MARK: - Option -

extension BetaFlags {
    enum Option: String, Hashable, Equatable, Codable, CaseIterable, Identifiable {

        case vibrateOnScan
        case enableCoinbase
        case enableSend

        var id: String {
            localizedTitle
        }

        var localizedTitle: String {
            switch self {
            case .vibrateOnScan:
                return "Vibrate on scan"
            case .enableCoinbase:
                return "Enable Coinbase"
            case .enableSend:
                return "Send Cash"
            }
        }

        var localizedDescription: String {
            switch self {
            case .vibrateOnScan:
                return "If enabled, the device will vibrate to indicate that the camera has registered the code on the bill"
            case .enableCoinbase:
                return "If enabled, Coinbase onramp will be available regardless of region"
            case .enableSend:
                return "If enabled, the Send feature is available from the scan screen"
            }
        }
    }
}

extension BetaFlags {
    static let mock = BetaFlags()
}
