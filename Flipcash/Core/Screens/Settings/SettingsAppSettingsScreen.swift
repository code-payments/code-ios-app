//
//  SettingsAppSettingsScreen.swift
//  Flipcash
//
//  Created by Raul Riera on 2026-04-27.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

struct SettingsAppSettingsScreen: View {

    private let insets = EdgeInsets(top: 25, leading: 0, bottom: 25, trailing: 0)

    var body: some View {
        Background(color: .backgroundMain) {
            ScrollView(showsIndicators: false) {
                AppSettingsList(insets: insets)
            }
            .padding(.horizontal, 20)
        }
        .navigationTitle("App Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AppSettingsList: View {

    @Environment(AppRouter.self) private var router
    @Environment(Preferences.self) private var preferences

    let insets: EdgeInsets

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Row(insets: insets) {
                Image.asset(.camera).frame(minWidth: 45)
                Toggle("Auto Start Camera", isOn: cameraAutoStartDisabledBinding())
                    .multilineTextAlignment(.leading)
                    .truncationMode(.tail)
                    .padding(.trailing, 2)
                    .tint(.textSuccess)
            }

            SettingsRow(
                systemImage: "clock.arrow.circlepath",
                title: "Auto-Return",
                insets: insets
            ) {
                router.push(.settingsAutoReturn)
            }
        }
        .font(.appDisplayXS)
        .foregroundStyle(.textMain)
    }

    private func cameraAutoStartDisabledBinding() -> Binding<Bool> {
        Binding(
            get: { !preferences.cameraAutoStartDisabled },
            set: { enabled in
                preferences.cameraAutoStartDisabled = !enabled
            }
        )
    }
}
