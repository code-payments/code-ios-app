//
//  LeaderboardSectionTitle.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

struct LeaderboardSectionTitle: View {
    var body: some View {
        Text("Leaderboard")
            .font(.appTextLarge)
            .foregroundStyle(Color.textMain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 12)
    }
}
