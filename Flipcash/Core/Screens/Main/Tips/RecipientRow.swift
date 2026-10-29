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
    /// empty-chat placeholder is italic, and a chat's preview sets its author in bold.
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
        HStack(spacing: RecipientRowMetrics.avatarGap) {
            ContactAvatarView(
                id: avatarID,
                displayName: title,
                imageData: imageData,
                blurhash: blurhash,
                size: RecipientRowMetrics.avatarSize
            )
            VStack(alignment: .leading, spacing: 3) {
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
                        .font(.default(size: 14, weight: .regular))
                        .foregroundStyle(Color.textSecondary)
                        .tracking(0.16)
                        .lineLimit(2)
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

/// The avatar column every conversation row shares; a row above the chats lines up with it.
nonisolated enum RecipientRowMetrics {
    /// The avatar's diameter.
    static let avatarSize: CGFloat = 52
    /// The space between the avatar and the text.
    static let avatarGap: CGFloat = 12
}

private extension View {
    /// Row chrome shared by every conversation row: list insets, clear
    /// background, separator tint, and single-element button accessibility.
    func recipientRowChrome(accessibilityLabel: String) -> some View {
        self
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets(top: 14, leading: 20, bottom: 14, trailing: 20))
            // Starts where the title does, past the avatar and its gap.
            .alignmentGuide(.listRowSeparatorLeading) { _ in
                RecipientRowMetrics.avatarSize + RecipientRowMetrics.avatarGap
            }
            .listRowBackground(Color.clear)
            .listRowSeparatorTint(.rowSeparator)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(accessibilityLabel))
            .accessibilityAddTraits(.isButton)
    }
}

/// A row's trailing accessory: the last activity's time (or an "Unknown Contact" pill), followed
/// by a dot while the chat has unread messages.
struct RecipientRowAccessory: View {

    let timestamp: Date
    let isUnknown: Bool
    let hasUnread: Bool

    var body: some View {
        HStack(spacing: 6) {
            if isUnknown {
                Text("Unknown Contact")
                    .fixedSize(horizontal: true, vertical: false)
                    .pill()
            } else {
                Text(timestamp.formattedChatListTime())
                    .font(.default(size: 14, weight: .regular))
                    .foregroundStyle(hasUnread ? Color.unreadIndicator : Color.textSecondary)
            }
            if hasUnread {
                Circle()
                    .fill(Color.unreadIndicator)
                    .frame(width: 9, height: 9)
            }
        }
    }
}
