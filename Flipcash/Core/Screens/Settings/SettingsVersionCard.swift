//
//  SettingsVersionCard.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// What the Settings version card shows. Debug is checked first, so a debug build never pins the
/// card or offers an update whatever the store lookup says.
nonisolated enum SettingsVersionCardState: Equatable {
    case upToDate
    case updateAvailable(AppVersion)
    case debug

    init(newerVersion: AppVersion?, isDebugBuild: Bool) {
        if isDebugBuild {
            self = .debug
        } else if let newerVersion {
            self = .updateAvailable(newerVersion)
        } else {
            self = .upToDate
        }
    }

    /// Whether the card floats over the bottom of the list instead of sitting at the end of it.
    var isPinned: Bool {
        switch self {
        case .updateAvailable: true
        case .upToDate, .debug: false
        }
    }

    /// Whether the You tab's gear carries the attention dot.
    var showsGearDot: Bool { isPinned }

    /// Whether tapping the card counts toward the beta-access easter egg.
    var allowsBetaToggle: Bool { !isPinned }

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
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Flipcash \(AppMeta.version)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.textMain)
                    if state == .debug {
                        Text("Debug")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.textSecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.textSecondary.opacity(0.2)))
                    }
                }
                subtitle
            }
            .lineLimit(1)

            Spacer(minLength: 0)

            trailing
        }
        .padding(.horizontal, 16)
        .frame(height: 64)
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

    /// Liquid Glass on iOS 26; a material on iOS 18, which has no glass.
    @ViewBuilder
    private var pinnedBackground: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.boxRadius, style: .continuous)
        if #available(iOS 26.0, *) {
            shape.fill(Color.clear).glassEffect(.regular, in: shape)
        } else {
            shape.fill(.ultraThinMaterial)
        }
    }

    @ViewBuilder
    private var subtitle: some View {
        switch state {
        case .updateAvailable(let version):
            Text("\(version.description) available")
                .font(.system(size: 12))
                .foregroundStyle(Color.textSuccess)
                .accessibilityIdentifier("settings-version-subtitle")
        case .upToDate, .debug:
            Text("Build \(AppMeta.build)")
                .font(.system(size: 12))
                .foregroundStyle(Color.textSecondary)
                .accessibilityIdentifier("settings-version-subtitle")
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch state {
        case .updateAvailable:
            ProfileEditCapsule(title: "Update", action: onUpdate)
                .accessibilityIdentifier("settings-version-update")
        case .upToDate:
            Text("Up to date \u{2713}")
                .font(.system(size: 12))
                .foregroundStyle(Color.textSecondary)
        case .debug:
            EmptyView()
        }
    }
}
