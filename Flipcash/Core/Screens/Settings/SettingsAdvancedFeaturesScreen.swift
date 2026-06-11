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
    @Environment(Session.self) private var session

    private let insets = EdgeInsets(top: 25, leading: 0, bottom: 25, trailing: 0)

    @State private var isShowingGoldBarDemo = false

    var body: some View {
        Background(color: .backgroundMain) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    SettingsRow(systemImage: "slider.horizontal.3", title: "Bill Designer", insets: insets) {
                        Task {
                            router.dismissSheet()
                            try await Task.delay(milliseconds: 250)
                            session.isShowingBillDesigner = true
                        }
                    }

                    SettingsRow(systemImage: "doc.text", title: "Application Logs", insets: insets) {
                        router.push(.settingsApplicationLogs)
                    }

                    SettingsRow(systemImage: "rectangle.portrait.on.rectangle.portrait.angled", title: "Gold Bar Demo", insets: insets) {
                        GoldBarTextureStore.shared.preheat(key: GoldBarDemoScreen.demoKey)
                        isShowingGoldBarDemo = true
                    }
                }
                .font(.appDisplayXS)
                .foregroundStyle(.textMain)
            }
            .padding(.horizontal, 20)
        }
        .navigationTitle("Advanced Features")
        .toolbarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $isShowingGoldBarDemo) {
            GoldBarDemoScreen()
        }
    }
}
