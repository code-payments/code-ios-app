//
//  SettingsVersionCard.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// What the Settings version card shows, picked in this order: debug, a store update, a newer TestFlight
/// build for a TestFlight install, a newer TestFlight build for staff on a store install, then up to
/// date. Debug is first so a debug build never pins the card or offers an install, and the store card
/// wins over a newer internal build.
nonisolated enum SettingsVersionCardState: Equatable {
    case upToDate
    case updateAvailable(AppVersion)
    /// A TestFlight install with a newer TestFlight build waiting.
    case testFlightUpdate(build: Int)
    /// A store install, on a staff account, with a TestFlight build newer than the installed one.
    case testFlightNewer(build: Int)
    /// A debug build, with the newest TestFlight build when the manifest could be read.
    case debug(latestTestFlightBuild: Int?)

    init(
        newerVersion: AppVersion?,
        isDebugBuild: Bool,
        channel: InstallChannel = .store,
        installedBuild: Int? = nil,
        latestTestFlightBuild: Int? = nil,
        isStaff: Bool = false
    ) {
        let newerTestFlightBuild: Int? = {
            guard let installedBuild, let latestTestFlightBuild, latestTestFlightBuild > installedBuild else { return nil }
            return latestTestFlightBuild
        }()
        if isDebugBuild {
            self = .debug(latestTestFlightBuild: latestTestFlightBuild)
        } else if let newerVersion {
            self = .updateAvailable(newerVersion)
        } else if channel == .testFlight, let newerTestFlightBuild {
            self = .testFlightUpdate(build: newerTestFlightBuild)
        } else if channel == .store, isStaff, let newerTestFlightBuild {
            self = .testFlightNewer(build: newerTestFlightBuild)
        } else {
            self = .upToDate
        }
    }

    /// Whether the card floats over the bottom of the list instead of sitting at the end of it.
    var isPinned: Bool {
        switch self {
        case .updateAvailable, .testFlightUpdate, .testFlightNewer: true
        case .upToDate, .debug: false
        }
    }

    /// Whether the You tab's gear carries the attention dot. A staff user on a store build isn't behind
    /// on anything, so the newer TestFlight build doesn't raise it.
    var showsGearDot: Bool {
        switch self {
        case .updateAvailable, .testFlightUpdate: true
        case .upToDate, .testFlightNewer, .debug: false
        }
    }

    /// Whether tapping the card counts toward the beta-access easter egg.
    var allowsBetaToggle: Bool { !isPinned }

    /// Whether the title carries the build number, as it does on internal, debug and staff cards.
    var titleShowsBuild: Bool {
        switch self {
        case .testFlightUpdate, .testFlightNewer, .debug: true
        case .upToDate, .updateAvailable: false
        }
    }

    /// Whether the build the app is running is a debug build. `-SettingsCardAsRelease YES` lets a
    /// debug build render the release treatments for inspection.
    static var isDebugBuild: Bool {
        #if DEBUG
        !UserDefaults.standard.bool(forKey: "SettingsCardAsRelease")
        #else
        false
        #endif
    }
}

/// The compact card at the bottom of Settings: the installed version, and either its build or the
/// newer version waiting in the store.
struct SettingsVersionCard: View {

    let state: SettingsVersionCardState
    let onTapVersion: () -> Void
    let onUpdate: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textMain)
                    if case .debug = state {
                        Text("Debug")
                            .font(.appTextCaption)
                            .foregroundStyle(Color.textSecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.textSecondary.opacity(0.2)))
                    }
                }
                subtitle
            }
            .lineLimit(1)
            .padding(.top, 15)

            Spacer(minLength: 0)

            trailing
                .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 16)
        .frame(height: 70)
        .background {
            if state.isPinned {
                pinnedBackground
            } else {
                RoundedRectangle(cornerRadius: Metrics.boxRadius, style: .continuous)
                    .fill(Color.backgroundRow)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if state.allowsBetaToggle { onTapVersion() }
        }
        .padding(.horizontal, 20)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("you-version-footer")
    }

    /// Dark glass: the row tone at 62% over a 24pt-blur material, with a 10% white edge and a soft
    /// shadow. The same recipe on every OS, so iOS 18 and 26 match.
    private var pinnedBackground: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.boxRadius, style: .continuous)
        return shape
            .fill(.ultraThinMaterial)
            .overlay(shape.fill(Color(red: 28 / 255, green: 28 / 255, blue: 29 / 255).opacity(0.62)))
            .overlay(shape.strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
            .shadow(color: .black.opacity(0.25), radius: 16, y: 4)
    }

    private var title: String {
        state.titleShowsBuild ? "Flipcash \(AppMeta.version) (\(AppMeta.build))" : "Flipcash \(AppMeta.version)"
    }

    @ViewBuilder
    private var subtitle: some View {
        switch state {
        case .updateAvailable(let version):
            caption("\(version.description) available", color: .textSuccess)
        case .testFlightUpdate(let build):
            caption("TestFlight build \(build) available", color: .textSuccess)
        case .testFlightNewer(let build):
            caption("TestFlight build \(build) is newer", color: .textSuccess)
        case .debug(let build?):
            caption("Latest TestFlight: build \(build)", color: .textSecondary)
        case .debug(nil):
            EmptyView()
        case .upToDate:
            caption("Build \(AppMeta.build)", color: .textSecondary)
        }
    }

    private func caption(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.appTextCaption)
            .foregroundStyle(color)
            .accessibilityIdentifier("settings-version-subtitle")
    }

    @ViewBuilder
    private var trailing: some View {
        switch state {
        case .updateAvailable, .testFlightUpdate:
            ProfileEditCapsule(title: "Update", action: onUpdate)
                .accessibilityIdentifier("settings-version-update")
        case .testFlightNewer:
            ProfileEditCapsule(title: "Try it", action: onUpdate)
                .accessibilityIdentifier("settings-version-try-it")
        case .upToDate:
            Text("Up to date \u{2713}")
                .font(.appTextCaption)
                .foregroundStyle(Color.textSecondary)
        case .debug:
            EmptyView()
        }
    }
}
