//
//  SettingsAdvancedBetaFeaturesScreen.swift
//  Flipcash
//
//  Created by Raul Riera on 2026-06-18.
//

import SwiftUI
import FlipcashCore
import FlipcashUI

struct SettingsAdvancedBetaFeaturesScreen: View {

    @Environment(BetaFlags.self) private var betaFlags

    private let insets = EdgeInsets(top: 25, leading: 0, bottom: 25, trailing: 0)

    var body: some View {
        Background(color: .backgroundMain) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 12) {
                        Image(systemName: "paperplane")
                            .frame(minWidth: 45)
                        Toggle("Send Cash", isOn: betaFlags.bindingFor(option: .enableSend))
                            .tint(.textSuccess)
                    }
                    .padding(insets)
                    .vSeparator(color: .rowSeparator, position: .bottom)
                }
                .font(.appDisplayXS)
                .foregroundStyle(.textMain)
                .padding(.horizontal, 20)
            }
        }
        .navigationTitle("Beta Features")
        .toolbarTitleDisplayMode(.inline)
    }
}
