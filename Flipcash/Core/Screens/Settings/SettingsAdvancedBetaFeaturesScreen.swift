//
//  SettingsAdvancedBetaFeaturesScreen.swift
//  Flipcash
//
//  Created by Raul Riera on 2026-06-18.
//

import SwiftUI
import FlipcashUI

struct SettingsAdvancedBetaFeaturesScreen: View {

    @Environment(BetaFlags.self) private var betaFlags

    private let options = BetaFlags.Option.allCases.filter { $0.availability == .publicBeta }

    var body: some View {
        Background(color: .backgroundMain) {
            if options.isEmpty {
                ContentUnavailableView {
                    Text("No Beta Features")
                        .font(.appTextLarge)
                        .foregroundStyle(Color.textMain)
                } description: {
                    Text("There are no beta features available right now.")
                        .font(.appTextMedium)
                        .foregroundStyle(Color.textSecondary)
                }
            } else {
                LazyTable(spacing: 0) {
                    ForEach(options) { option in
                        BetaFlagToggleRow(option: option, isOn: betaFlags.bindingFor(option: option))
                    }
                }
            }
        }
        .navigationTitle("Beta Features")
        .toolbarTitleDisplayMode(.inline)
    }
}

// MARK: - Previews -

#Preview {
    NavigationStack {
        SettingsAdvancedBetaFeaturesScreen()
    }
    .environment(BetaFlags.mock)
    .preferredColorScheme(.dark)
}
