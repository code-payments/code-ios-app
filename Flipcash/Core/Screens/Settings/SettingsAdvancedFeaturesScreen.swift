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

    #if DEBUG
    @AppStorage("usesUIKitChat") private var usesUIKitChat = false
    #endif

    private let insets = EdgeInsets(top: 25, leading: 0, bottom: 25, trailing: 0)

    var body: some View {
        Background(color: .backgroundMain) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    SettingsRow(asset: .debug, title: "Beta Features", badge: .beta, insets: insets) {
                        router.push(.settingsAdvancedBetaFeatures)
                    }

                    SettingsRow(systemImage: "doc.text", title: "Application Logs", insets: insets) {
                        router.push(.settingsApplicationLogs)
                    }

                    #if DEBUG
                    Toggle("Use UIKit chat in real conversations", isOn: $usesUIKitChat)
                        .padding(.vertical, 25)
                    #endif
                }
                .font(.appDisplayXS)
                .foregroundStyle(.textMain)
                .padding(.horizontal, 20)
            }
        }
        .navigationTitle("Advanced")
        .toolbarTitleDisplayMode(.inline)
    }
}
