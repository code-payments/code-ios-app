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
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Flipcash \(AppMeta.version)")
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textMain)
                    if state == .debug {
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

    @ViewBuilder
    private var subtitle: some View {
        switch state {
        case .updateAvailable(let version):
            Text("\(version.description) available")
                .font(.appTextCaption)
                .foregroundStyle(Color.textSuccess)
                .accessibilityIdentifier("settings-version-subtitle")
        case .upToDate, .debug:
            Text("Build \(AppMeta.build)")
                .font(.appTextCaption)
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
                .font(.appTextCaption)
                .foregroundStyle(Color.textSecondary)
        case .debug:
            EmptyView()
        }
    }
}
