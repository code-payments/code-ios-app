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

    /// "3 people want to join Moony", shown under the row's title.
    let subtitle: String
    let count: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Sized and filled like a chat row's avatar, so the row lines up with the list (node 11214:67).
                Circle()
                    .fill(Color.avatarPlaceholderTop)
                    .frame(width: 44, height: 44)
                    .overlay {
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color.textMain)
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Join Requests")
                        .font(.appTextMedium)
                        .foregroundStyle(Color.textMain)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 12)
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("chat-join-requests-row")
    }
}
