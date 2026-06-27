//
//  SettingsAdvancedBetaFeaturesScreen.swift
//  Flipcash
//
//  Created by Raul Riera on 2026-06-18.
//

import SwiftUI
import FlipcashUI

struct SettingsAdvancedBetaFeaturesScreen: View {

    var body: some View {
        Background(color: .backgroundMain) {
            ContentUnavailableView {
                Text("No Beta Features")
                    .font(.appTextLarge)
                    .foregroundStyle(Color.textMain)
            } description: {
                Text("There are no beta features available right now.")
                    .font(.appTextMedium)
                    .foregroundStyle(Color.textSecondary)
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
    .preferredColorScheme(.dark)
}
