//
//  ProfileStatsCard.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// The two figures under a profile header: what it costs to start a chat, and when the user joined.
struct ProfileStatsCard: View {

    let minimumToChat: FiatAmount?
    let joinedAt: Date?

    var body: some View {
        HStack(spacing: 0) {
            stat(
                title: "Minimum to Chat",
                value: minimumToChat?.formatted() ?? "—",
                identifier: "profile-stat-minimum"
            )

            Color.rowSeparator
                .frame(width: 1, height: 32)

            stat(
                title: "Date Joined",
                value: joinedAt?.formatted(.dateTime.month(.abbreviated).year()) ?? "—",
                identifier: "profile-stat-joined"
            )
        }
        .padding(.vertical, 16)
        .background(Color.backgroundRow, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func stat(title: String, value: String, identifier: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.appTextMedium)
                .foregroundStyle(Color.textMain)
            Text(title)
                .font(.appTextSmall)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}
