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
        HStack(spacing: ChatListTuning.avatarGap) { // LOCAL-TUNER
            ContactAvatarView(
                id: avatarID,
                displayName: title,
                imageData: imageData,
                blurhash: blurhash,
                size: ChatListTuning.avatarSize // LOCAL-TUNER
            )
            VStack(alignment: .leading, spacing: ChatListTuning.lineGap) { // LOCAL-TUNER
                HStack(alignment: ChatListTuning.dateBaseline ? .firstTextBaseline : .top, spacing: 6) { // LOCAL-TUNER
                    // Beside the title, as in the transcript's title bar: the mute belongs to the
                    // chat, and the title names it. A long title truncates; the bell never does.
                    HStack(spacing: 0) {
                        Text(title)
                            .font(.default(size: ChatListTuning.titleSize, weight: ChatListTuning.titleWeight.weight)) // LOCAL-TUNER
                            .foregroundStyle(ChatListTuning.titleColor) // LOCAL-TUNER
                            .tracking(ChatListTuning.titleTracking) // LOCAL-TUNER
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
                    Text(ChatListTuning.styledPreview(subtitle)) // LOCAL-TUNER
                        .font(.default(size: ChatListTuning.previewSize, weight: ChatListTuning.previewWeight.weight)) // LOCAL-TUNER
                        .foregroundStyle(ChatListTuning.previewColor) // LOCAL-TUNER
                        .tracking(ChatListTuning.previewTracking) // LOCAL-TUNER
                        .lineLimit(ChatListTuning.previewLines) // LOCAL-TUNER
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
            .listRowInsets(EdgeInsets(top: ChatListTuning.rowPaddingY, leading: ChatListTuning.rowPaddingX, bottom: ChatListTuning.rowPaddingY, trailing: ChatListTuning.rowPaddingX)) // LOCAL-TUNER
            .listRowSeparator(ChatListTuning.separators ? .automatic : .hidden) // LOCAL-TUNER
            .alignmentGuide(.listRowSeparatorLeading) { _ in ChatListTuning.separatorInset } // LOCAL-TUNER
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
        HStack(spacing: ChatListTuning.dateGap) { // LOCAL-TUNER
            if isUnknown {
                Text("Unknown Contact")
                    .fixedSize(horizontal: true, vertical: false)
                    .pill()
            } else {
                Text(ChatListTuning.date(timestamp)) // LOCAL-TUNER
                    .font(.default(size: ChatListTuning.dateSize, weight: ChatListTuning.dateWeight.weight)) // LOCAL-TUNER
                    .tracking(ChatListTuning.dateTracking) // LOCAL-TUNER
                    .foregroundStyle(hasUnread && ChatListTuning.dateTintsUnread ? Color.unreadIndicator : ChatListTuning.dateColor) // LOCAL-TUNER
            }
            if let count, ChatListTuning.unreadStyle == .count {
                UnreadCountPill(count: count)
            } else if hasUnread, ChatListTuning.unreadStyle != .none {
                Circle()
                    .fill(Color.unreadIndicator)
                    .frame(width: ChatListTuning.unreadDotSize, height: ChatListTuning.unreadDotSize) // LOCAL-TUNER
            } else if ChatListTuning.showsChevron { // LOCAL-TUNER
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

    var body: some View {
        Text(UnreadCountLabel.text(for: count))
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

// LOCAL-TUNER: every value in a chat list row, for tuning. Groups start "Chat list" so the panel can scope to them.
enum ChatListTuning { // LOCAL-TUNER
    static var avatarSize: CGFloat { Tuner.value("Chat list Row/Avatar size", default: 52, in: 28...72, unit: .points) } // LOCAL-TUNER
    static var avatarGap: CGFloat { Tuner.value("Chat list Row/Avatar to text", default: 12, in: 4...24, unit: .points) } // LOCAL-TUNER
    static var rowPaddingY: CGFloat { Tuner.value("Chat list Row/Padding Y", default: 14, in: 4...28, unit: .points) } // LOCAL-TUNER
    static var rowPaddingX: CGFloat { Tuner.value("Chat list Row/Padding X", default: 20, in: 8...32, unit: .points) } // LOCAL-TUNER
    static var separators: Bool { Tuner.value("Chat list Row/Separators", default: true) } // LOCAL-TUNER
    /// Where the separator starts: 0 is the row's edge; avatar + gap lines it up with the text. // LOCAL-TUNER
    static var separatorInset: CGFloat { Tuner.value("Chat list Row/Separator inset", default: 56, in: 0...100, unit: .points) } // LOCAL-TUNER
    static var lineGap: CGFloat { Tuner.value("Chat list Row/Title to preview", default: 3, in: 0...12, unit: .points) } // LOCAL-TUNER

    static var titleSize: CGFloat { Tuner.value("Chat list Title/Size", default: 16, in: 12...22, unit: .points) } // LOCAL-TUNER
    static var titleWeight: ChatListWeight { Tuner.value("Chat list Title/Weight", default: ChatListWeight.bold) } // LOCAL-TUNER
    static var titleColor: Color { Tuner.value("Chat list Title/Color", default: Color.textMain) } // LOCAL-TUNER

    static var previewSize: CGFloat { Tuner.value("Chat list Preview/Size", default: 14, in: 11...18, unit: .points) } // LOCAL-TUNER
    static var previewWeight: ChatListWeight { Tuner.value("Chat list Preview/Weight", default: ChatListWeight.regular) } // LOCAL-TUNER
    static var previewColor: Color { Tuner.value("Chat list Preview/Color", default: Color.textSecondary) } // LOCAL-TUNER
    static var previewTracking: CGFloat { Tuner.value("Chat list Preview/Tracking", default: 0.16, in: -1...2, unit: .points) } // LOCAL-TUNER
    static var titleTracking: CGFloat { Tuner.value("Chat list Title/Tracking", default: 0, in: -1...2, unit: .points) } // LOCAL-TUNER
    static var dateTracking: CGFloat { Tuner.value("Chat list Date/Tracking", default: 0, in: -1...2, unit: .points) } // LOCAL-TUNER
    static var previewLines: Int { Tuner.value("Chat list Preview/Lines", default: 2, in: 1...3) } // LOCAL-TUNER
    static var authorWeight: ChatListWeight { Tuner.value("Chat list Preview/Author weight", default: ChatListWeight.bold) } // LOCAL-TUNER
    static var authorColor: Color { Tuner.value("Chat list Preview/Author color", default: Color.textSecondary) } // LOCAL-TUNER

    static var dateStyle: ChatListDateStyle { Tuner.value("Chat list Date/Style", default: ChatListDateStyle.shortWeekday) } // LOCAL-TUNER
    static var todayStyle: ChatListTodayStyle { Tuner.value("Chat list Date/Today shows", default: ChatListTodayStyle.time) } // LOCAL-TUNER
    static var yesterdayWord: Bool { Tuner.value("Chat list Date/Say Yesterday", default: true) } // LOCAL-TUNER
    static var dateSize: CGFloat { Tuner.value("Chat list Date/Size", default: 14, in: 10...18, unit: .points) } // LOCAL-TUNER
    static var dateWeight: ChatListWeight { Tuner.value("Chat list Date/Weight", default: ChatListWeight.regular) } // LOCAL-TUNER
    static var dateColor: Color { Tuner.value("Chat list Date/Color", default: Color.textSecondary) } // LOCAL-TUNER
    static var dateTintsUnread: Bool { Tuner.value("Chat list Date/Blue when unread", default: true) } // LOCAL-TUNER
    static var dateBaseline: Bool { Tuner.value("Chat list Date/Align to title baseline", default: false) } // LOCAL-TUNER
    static var dateGap: CGFloat { Tuner.value("Chat list Date/Gap to badge", default: 6, in: 0...16, unit: .points) } // LOCAL-TUNER

    static var unreadStyle: ChatListUnreadStyle { Tuner.value("Chat list Unread/Style", default: ChatListUnreadStyle.dot) } // LOCAL-TUNER
    static var unreadDotSize: CGFloat { Tuner.value("Chat list Unread/Dot size", default: 9, in: 4...16, unit: .points) } // LOCAL-TUNER
    static var showsChevron: Bool { Tuner.value("Chat list Row/Show chevron", default: false) } // LOCAL-TUNER

    /// The preview with a leading "Name:" set apart in its own weight and colour. // LOCAL-TUNER
    static func styledPreview(_ text: AttributedString) -> AttributedString { // LOCAL-TUNER
        let plain = String(text.characters) // LOCAL-TUNER
        guard let colon = plain.firstIndex(of: ":"), plain.distance(from: plain.startIndex, to: colon) <= 28, // LOCAL-TUNER
              let end = text.characters.index(text.startIndex, offsetBy: plain.distance(from: plain.startIndex, to: colon) + 1, limitedBy: text.endIndex) // LOCAL-TUNER
        else { return text } // LOCAL-TUNER
        var styled = text // LOCAL-TUNER
        styled[text.startIndex..<end].font = .default(size: previewSize, weight: authorWeight.weight) // LOCAL-TUNER
        styled[text.startIndex..<end].foregroundColor = authorColor // LOCAL-TUNER
        return styled // LOCAL-TUNER
    } // LOCAL-TUNER

    /// The row's timestamp in the picked style. // LOCAL-TUNER
    static func date(_ date: Date) -> String { // LOCAL-TUNER
        let calendar = Calendar.current // LOCAL-TUNER
        if calendar.isDateInToday(date) { // LOCAL-TUNER
            switch todayStyle { // LOCAL-TUNER
            case .time: return date.formatted(date: .omitted, time: .shortened) // LOCAL-TUNER
            case .today: return "Today" // LOCAL-TUNER
            case .now: return date.formatted(.relative(presentation: .named, unitsStyle: .narrow)) // LOCAL-TUNER
            } // LOCAL-TUNER
        } // LOCAL-TUNER
        if yesterdayWord, calendar.isDateInYesterday(date) { return "Yesterday" } // LOCAL-TUNER
        let withinWeek = date > calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: .now))! // LOCAL-TUNER
        switch dateStyle { // LOCAL-TUNER
        case .relative: return date.formattedRelatively(useTimeForToday: true) // LOCAL-TUNER
        case .shortWeekday: return withinWeek ? date.formatted(.dateTime.weekday(.abbreviated)) : date.formatted(.dateTime.month(.abbreviated).day()) // LOCAL-TUNER
        case .fullWeekday: return withinWeek ? date.formatted(.dateTime.weekday(.wide)) : date.formatted(.dateTime.month(.abbreviated).day()) // LOCAL-TUNER
        case .monthDay: return date.formatted(.dateTime.month(.abbreviated).day()) // LOCAL-TUNER
        case .numeric: return date.formatted(.dateTime.month(.defaultDigits).day()) // LOCAL-TUNER
        case .ago: return date.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated)) // LOCAL-TUNER
        } // LOCAL-TUNER
    } // LOCAL-TUNER
} // LOCAL-TUNER

enum ChatListWeight: String, TunableEnum { // LOCAL-TUNER
    case regular, medium, semibold, bold // LOCAL-TUNER
    var weight: Font.Weight { switch self { case .regular: .regular; case .medium: .medium; case .semibold: .semibold; case .bold: .bold } } // LOCAL-TUNER
} // LOCAL-TUNER
enum ChatListDateStyle: String, TunableEnum { case relative, shortWeekday, fullWeekday, monthDay, numeric, ago } // LOCAL-TUNER
enum ChatListTodayStyle: String, TunableEnum { case time, today, now } // LOCAL-TUNER
enum ChatListUnreadStyle: String, TunableEnum { case count, dot, none } // LOCAL-TUNER

