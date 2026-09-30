//
//  MentionSuggestionList.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

/// The mention list's measurements, kept together for the design pass.
enum MentionListMetrics {
    /// One row's height, the same as the composer row's content.
    static let rowHeight: CGFloat = BarMetrics.contentHeight
    /// The margin around the list's ground, matching the reply strip's.
    static let inset: CGFloat = 12
    /// The row's horizontal padding inside the ground.
    static let rowPadding: CGFloat = 14
    /// The gap between a row's avatar, name and handle.
    static let rowSpacing: CGFloat = 10
    static let avatarDiameter: CGFloat = 32

    /// The padding under the list: none above a reply strip, whose own top margin separates the two;
    /// the strip's remainder above the composer row, so the gap matches the strip's.
    static func bottomPadding(replyOpen: Bool) -> CGFloat {
        replyOpen ? 0 : inset - BarMetrics.contentPadding
    }

    /// What the list adds to the bar besides its rows.
    static func chrome(replyOpen: Bool) -> CGFloat {
        inset + bottomPadding(replyOpen: replyOpen)
    }
}

/// The members matching the `@word` being typed, in the reply strip's style: the same glass ground,
/// corner radius and margins, hairline dividers, and a scroll past `maxRows`.
struct MentionSuggestionList: View {

    let candidates: [ConversationMember]
    let maxRows: Int
    let replyOpen: Bool
    let onPick: (ConversationMember) -> Void

    private var visibleRows: Int { min(maxRows, candidates.count) }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(candidates.enumerated()), id: \.element.id) { index, member in
                    Button { onPick(member) } label: { MentionRow(member: member) }
                        .buttonStyle(.plain)
                    if index < candidates.count - 1 {
                        Rectangle()
                            .fill(Color.textSecondary.opacity(0.25))
                            .frame(height: 1 / UIScreen.main.scale)
                            .padding(
                                .leading,
                                MentionListMetrics.rowPadding + MentionListMetrics.avatarDiameter + MentionListMetrics.rowSpacing
                            )
                    }
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: CGFloat(visibleRows) * MentionListMetrics.rowHeight)
        .clipShape(RoundedRectangle(cornerRadius: BarMetrics.cornerRadius))
        .glassFieldBackground(cornerRadius: BarMetrics.cornerRadius)
        .padding(.horizontal, MentionListMetrics.inset)
        .padding(.top, MentionListMetrics.inset)
        .padding(.bottom, MentionListMetrics.bottomPadding(replyOpen: replyOpen))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mention-suggestion-list")
    }
}

private struct MentionRow: View {
    let member: ConversationMember

    var body: some View {
        HStack(spacing: MentionListMetrics.rowSpacing) {
            ContactAvatarView(
                id: member.id,
                displayName: member.displayName,
                size: MentionListMetrics.avatarDiameter
            )
            Text(member.displayName)
                .font(.appTextHeading)
                .foregroundStyle(ComplementaryPalette.color(.middle, for: member.userID))
                .lineLimit(1)
            if let username = member.username {
                Text("@\(username.value)")
                    .font(.default(size: 14, weight: .medium))
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, MentionListMetrics.rowPadding)
        .frame(height: MentionListMetrics.rowHeight)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("mention-suggestion-\(member.username?.value ?? "")")
    }
}
