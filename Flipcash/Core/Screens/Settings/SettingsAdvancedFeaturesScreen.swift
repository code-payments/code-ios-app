//
//  SettingsAdvancedFeaturesScreen.swift
//  Flipcash
//
//  Created by Raul Riera on 2026-04-27.
//

import SwiftUI
import FlipcashUI

struct SettingsAdvancedFeaturesScreen: View {

    @Environment(AppRouter.self) private var router

    private let insets = EdgeInsets(top: 25, leading: 0, bottom: 25, trailing: 0)

    var body: some View {
        Background(color: .backgroundMain) {
            ScrollView(showsIndicators: false) {
                list()
            }
            .padding(.horizontal, 20)
        }
        .navigationTitle("Advanced Features")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func list() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsRow(asset: .deposit, title: "Deposit Funds", insets: insets) {
                router.push(.depositCurrencyList, on: .settings)
            }
            SettingsRow(systemImage: "doc.text", title: "Application Logs", insets: insets) {
                router.push(.settingsApplicationLogs, on: .settings)
            }
        }
        .font(.appDisplayXS)
        .foregroundColor(.textMain)
    }
}
