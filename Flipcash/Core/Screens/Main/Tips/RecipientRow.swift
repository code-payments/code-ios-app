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
                size: 52
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
                    Text(Self.styledPreview(subtitle))
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

    /// The preview with a leading "Name:" set apart in bold. A subtitle that already carries its
    /// own colour, like a join-request line, is left as its builder styled it.
    private static func styledPreview(_ text: AttributedString) -> AttributedString {
        guard !text.runs.contains(where: { $0[AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute.self] != nil }) else { return text }
        let plain = String(text.characters)
        guard let colon = plain.firstIndex(of: ":"), plain.distance(from: plain.startIndex, to: colon) <= 28,
              let end = text.characters.index(text.startIndex, offsetBy: plain.distance(from: plain.startIndex, to: colon) + 1, limitedBy: text.endIndex)
        else { return text }
        var styled = text
        styled[text.startIndex..<end].font = Font.appTextSmall
        styled[text.startIndex..<end].foregroundColor = Color.textSecondary
        return styled
    }
}

private extension View {
    /// Row chrome shared by every conversation row: list insets, clear
    /// background, separator tint, and single-element button accessibility.
    func recipientRowChrome(accessibilityLabel: String) -> some View {
        self
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets(top: 14, leading: 20, bottom: 14, trailing: 20))
            .listRowSeparator(.automatic)
            .alignmentGuide(.listRowSeparatorLeading) { _ in 56 }
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
                Text(Self.label(for: timestamp))
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

    /// The time today, "Yesterday", a short weekday within the past week, and a short month and
    /// day before that.
    private static func label(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let weekAgo = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: .now))!
        return date > weekAgo
            ? date.formatted(.dateTime.weekday(.abbreviated))
            : date.formatted(.dateTime.month(.abbreviated).day())
    }
}
