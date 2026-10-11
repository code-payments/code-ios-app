//
//  JoinRequestsRow.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import FlipcashUI

/// The pinned row above Archived while a private group the user hosts has people waiting to join.
struct JoinRequestsRow: View {

    let title: String
    let count: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: "person.badge.plus")
                    .frame(minWidth: 45)
                    .foregroundStyle(Color.textSecondary)
                Text(title)
                    .font(.appTextMedium)
                    .foregroundStyle(Color.textMain)
                    .lineLimit(1)
                Spacer()
                // Secondary, like Archived's count: requests are not unread messages.
                Text("\(count)")
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textSecondary)
                Image(systemName: "chevron.right")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 9, height: 12)
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("chat-join-requests-row")
    }
}
