//
//  RecipientRow.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// Where a row's trailing accessory sits.
enum RecipientRowAccessoryPlacement {
    /// Centered in a full-height trailing column; the subtitle stays in the
    /// column beside it.
    case trailingColumn
    /// On the title's line (Messages/Mail style); the subtitle spans the row's
    /// full width below — the merged conversation feed.
    case titleLine
}

/// The chrome every conversation row shares: a full-row button with avatar,
/// title/subtitle, and an accessory. Used by the Tips conversations list.
struct RecipientRowScaffold<Trailing: View>: View {

    let avatarID: String
    let title: String
    /// The preview line. Attributed so a caller can style part of it — the
    /// empty-chat placeholder is italic while a real preview is not.
    let subtitle: AttributedString?
    let imageData: Data?
    var blurhash: String? = nil
    var accessoryPlacement: RecipientRowAccessoryPlacement = .trailingColumn
    /// The viewer's mute on this chat, drawn right after the title. The mute rather than a
    /// muted flag — ``MuteBell`` owns the countdown, because a timed one lapses with nothing sent.
    var mute: ConversationMuteState? = nil
    let accessibilityLabel: String
    let onTap: () -> Void
    @ViewBuilder let trailing: Trailing

    var body: some View {
        Button(action: onTap) {
            RecipientRowBody(
                avatarID: avatarID,
                title: title,
                subtitle: subtitle,
                imageData: imageData,
                blurhash: blurhash,
                accessoryPlacement: accessoryPlacement,
                mute: mute
            ) {
                trailing
            }
        }
        .recipientRowChrome(accessibilityLabel: accessibilityLabel)
    }
}

/// The visual content of a conversation row: avatar, title/subtitle, and an
/// accessory placed per `accessoryPlacement`.
struct RecipientRowBody<Trailing: View>: View {

    let avatarID: String
    let title: String
    let subtitle: AttributedString?
    let imageData: Data?
    var blurhash: String? = nil
    var accessoryPlacement: RecipientRowAccessoryPlacement = .trailingColumn
    var mute: ConversationMuteState? = nil
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            ContactAvatarView(
                id: avatarID,
                displayName: title,
                imageData: imageData,
                blurhash: blurhash,
                size: 44
            )
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .top, spacing: 6) {
                    // Beside the title, as in the transcript's title bar: the mute belongs to the
                    // chat, and the title names it. A long title truncates; the bell never does.
                    HStack(spacing: 0) {
                        Text(title)
                            .font(.appTextMedium)
                            .foregroundStyle(Color.textMain)
                            .lineLimit(1)
                        MuteBell(mute, leadingGap: 6)
                            .fixedSize()
                    }
                    if accessoryPlacement == .titleLine {
                        Spacer(minLength: 12)
                        trailing
                    }
                }
                if let subtitle {
                    Text(subtitle)
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                        .contentTransition(.opacity)
                        .transition(.opacity)
                }
            }
            // Cross-fade the subtitle when it changes — notably the "Typing…" ⇄ last-message swap, but
            // also a fresh message preview replacing the previous one.
            .animation(.easeInOut(duration: 0.2), value: subtitle)
            if accessoryPlacement == .trailingColumn {
                Spacer(minLength: 12)
                trailing
            }
        }
        .contentShape(Rectangle())
    }
}

private extension View {
    /// Row chrome shared by every conversation row: list insets, clear
    /// background, separator tint, and single-element button accessibility.
    func recipientRowChrome(accessibilityLabel: String) -> some View {
        self
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets(top: 14, leading: 20, bottom: 14, trailing: 20))
            .listRowBackground(Color.clear)
            .listRowSeparatorTint(.rowSeparator)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(accessibilityLabel))
            .accessibilityAddTraits(.isButton)
    }
}

/// A row's trailing accessory: a relative timestamp (or "Unknown Contact"
/// pill), the unread count, or a disclosure chevron.
struct RecipientRowAccessory: View {

    let timestamp: Date
    let isUnknown: Bool
    let hasUnread: Bool
    /// The count the unread pill carries. Nil while unread draws a bare dot: the count can't
    /// always be known, and a guessed number would be wrong.
    var unreadCount: Int? = nil

    var body: some View {
        let count = hasUnread ? unreadCount.flatMap { $0 > 0 ? $0 : nil } : nil
        // The design sets the count pill 4pt off the timestamp; the dot and chevron keep 6.
        HStack(spacing: count == nil ? 6 : 4) {
            if isUnknown {
                Text("Unknown Contact")
                    .fixedSize(horizontal: true, vertical: false)
                    .pill()
            } else {
                Text(timestamp.formattedRelatively(useTimeForToday: true))
                    .font(.appTextSmall)
                    .foregroundStyle(hasUnread ? Color.unreadIndicator : Color.textSecondary)
            }
            if let count {
                UnreadCountPill(count: count)
            } else if hasUnread {
                Circle()
                    .fill(Color.unreadIndicator)
                    .frame(width: 9, height: 9)
            } else {
                Image(systemName: "chevron.right")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 9, height: 12)
                    .foregroundStyle(Color.textSecondary)
            }
        }
    }
}

/// A chat's unread count beside its timestamp (node 10329:8245): dark digits on the unread
/// blue, 18pt tall, a circle for one digit that widens into a capsule for more.
private struct UnreadCountPill: View {

    let count: Int

    /// The tab bar's badge caps at the same point.
    private static let cap = 100

    var body: some View {
        Text(count > Self.cap ? "\(Self.cap)+" : "\(count)")
            .font(.appTextHeading)
            .tracking(-0.72)
            .foregroundStyle(Color.backgroundMain)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 4)
            .frame(minWidth: 18, minHeight: 18)
            .background(Color.unreadIndicator, in: .capsule)
    }
}
