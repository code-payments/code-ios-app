//
//  SettingsAdvancedFeaturesScreen.swift
//  Flipcash
//
//  Created by Raul Riera on 2026-04-27.
//

import SwiftUI
import FlipcashCore
import FlipcashUI

struct SettingsAdvancedFeaturesScreen: View {

    @Environment(AppRouter.self) private var router
    @Environment(BetaFlags.self) private var betaFlags

    private let insets = EdgeInsets(top: 25, leading: 0, bottom: 25, trailing: 0)

    var body: some View {
        Background(color: .backgroundMain) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 12) {
                        Image(systemName: "paperplane")
                            .frame(minWidth: 45)
                        Toggle("Beta Feature: Send Cash", isOn: betaFlags.bindingFor(option: .enableSend))
                            .tint(.textSuccess)
                    }
                    .padding(insets)
                    .vSeparator(color: .rowSeparator, position: .bottom)

                    SettingsRow(systemImage: "doc.text", title: "Application Logs", insets: insets) {
                        router.push(.settingsApplicationLogs)
                    }
                }
                .font(.appDisplayXS)
                .foregroundStyle(.textMain)
                .padding(.horizontal, 20)
            }
        }
        .navigationTitle("Advanced Features")
        .toolbarTitleDisplayMode(.inline)
    }
}
