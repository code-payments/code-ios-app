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
    /// The rule between rows, none after the last.
    static let dividerHeight: CGFloat = 1
    /// The rule's leading inset, lining it up with the name rather than the avatar.
    static let dividerInset: CGFloat = rowPadding + avatarDiameter + rowSpacing
    static let dividerColor = Color.white.opacity(0.1)
    /// The handle's colour, iOS's dark secondary label, which reads over the glass where
    /// `textSecondary` goes muddy.
    static let usernameColor = Color(red: 235 / 255, green: 235 / 255, blue: 245 / 255).opacity(0.6)
    /// The fill under a row while it's pressed, iOS's dark tertiary fill.
    static let pressedFill = Color(red: 118 / 255, green: 118 / 255, blue: 128 / 255).opacity(0.24)

    /// The list's height showing `rows` rows.
    static func listHeight(rows: Int) -> CGFloat {
        MentionRowCap.listHeight(rows: rows, rowHeight: rowHeight, divider: dividerHeight)
    }

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
                        .buttonStyle(MentionRowButtonStyle())
                    if index < candidates.count - 1 {
                        Rectangle()
                            .fill(MentionListMetrics.dividerColor)
                            .frame(height: MentionListMetrics.dividerHeight)
                            .padding(.leading, MentionListMetrics.dividerInset)
                    }
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: MentionListMetrics.listHeight(rows: visibleRows))
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
    @Environment(SessionContainer.self) private var sessionContainer

    let member: ConversationMember

    var body: some View {
        HStack(spacing: MentionListMetrics.rowSpacing) {
            ContactAvatarView(
                id: member.id,
                displayName: member.displayName,
                imageData: sessionContainer.profileAvatars.data(for: member.userID),
                blurhash: member.profilePicture?.thumbnailBlurhash,
                size: MentionListMetrics.avatarDiameter
            )
            Text(member.displayName)
                .font(.appTextHeading)
                .foregroundStyle(ComplementaryPalette.nameColor(for: member.userID))
                .lineLimit(1)
            if let username = member.username {
                Text("@\(username.value)")
                    .font(.default(size: 14, weight: .medium))
                    .foregroundStyle(MentionListMetrics.usernameColor)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, MentionListMetrics.rowPadding)
        .frame(height: MentionListMetrics.rowHeight)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("mention-suggestion-\(member.username?.value ?? "")")
        .task(id: member.profilePicture) {
            await sessionContainer.profileAvatars.load(userID: member.userID, picture: member.profilePicture)
        }
    }
}

/// A row's pressed state: the tertiary fill across the row's full width, under the glass's content.
private struct MentionRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? MentionListMetrics.pressedFill : Color.clear)
    }
}
