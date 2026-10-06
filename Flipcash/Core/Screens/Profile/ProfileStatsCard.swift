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
                valueFont: .default(size: 23, weight: .semibold),
                identifier: "profile-stat-minimum"
            )
            .frame(width: 176)

            Color.rowSeparator
                .frame(width: 1, height: 48)

            stat(
                title: "Date Joined",
                value: joinedAt?.formatted(.dateTime.month(.wide).year()) ?? "—",
                valueFont: .default(size: 17, weight: .medium),
                identifier: "profile-stat-joined"
            )
            .frame(maxWidth: .infinity)
        }
        .frame(height: 84)
        .background(Color.backgroundRow, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, ProfileHeaderView<EmptyView, EmptyView, EmptyView>.inset)
    }

    private func stat(title: String, value: String, valueFont: Font, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.default(size: 11, weight: .medium))
                .frame(minHeight: 15)
                .foregroundStyle(Color.textSecondary)
            Text(value)
                .font(valueFont)
                .foregroundStyle(Color.textMain)
        }
        .padding(.leading, 16)
        .padding(.top, 18)
        // Top-aligned so both labels share a baseline even though the values differ in size.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}
