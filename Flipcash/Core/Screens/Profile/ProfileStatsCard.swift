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
                valueFont: .appTextLarge,
                identifier: "profile-stat-minimum"
            )
            .frame(width: 176)

            Color.rowSeparator
                .frame(width: 1, height: 48)

            stat(
                title: "Date Joined",
                value: joinedAt?.formatted(.dateTime.month(.wide).year()) ?? "—",
                valueFont: .appTextLarge,
                identifier: "profile-stat-joined"
            )
            .frame(maxWidth: .infinity)
        }
        .frame(height: 84)
        .background(Color.backgroundRow, in: RoundedRectangle(cornerRadius: Metrics.boxRadius, style: .continuous))
        .padding(.horizontal, ProfileHeaderMetrics.inset)
    }

    private func stat(title: String, value: String, valueFont: Font, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.appTextCaption)
                .foregroundStyle(Color.textSecondary)
            Text(value)
                .font(valueFont)
                .foregroundStyle(Color.textMain)
        }
        .padding(.leading, 16)
        .padding(.top, 16)
        // Top-aligned so both labels share a baseline even though the values differ in size.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}
