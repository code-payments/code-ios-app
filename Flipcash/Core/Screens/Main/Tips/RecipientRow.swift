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
    /// Select mode: nil outside it; otherwise whether this row is picked. A leading circle shows it
    /// and the row tints while picked.
    var selection: Bool? = nil
    let accessibilityLabel: String
    let onTap: () -> Void
    @ViewBuilder let trailing: Trailing

    var body: some View {
        let isSelecting = selection != nil
        Button(action: onTap) {
            // Always laid out, never inserted: an inserted circle with a move transition slid on its
            // own while the content beside it jumped.
            RecipientRowSelectReveal(progress: isSelecting ? 1 : 0) {
                RecipientRowSelectCircle(isSelected: selection == true)
                    .opacity(isSelecting ? 1 : 0)
                    .accessibilityHidden(!isSelecting)
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
            // Inside the row: a List cell doesn't reliably pick up an animation set on the List.
            .animation(.smooth(duration: 0.3), value: isSelecting)
        }
        .recipientRowChrome(accessibilityLabel: accessibilityLabel, isSelected: selection == true)
        .accessibilityAddTraits(selection == true ? .isSelected : [])
    }
}

/// Lays out select mode's circle and the row content beside it from one `progress`: 0 outside
/// select mode, 1 in it. Takes exactly two subviews, the circle then the content.
///
/// Animating `progress` lays the whole row out again on every frame, so avatar, title, subtitle,
/// and trailing content move as one block, the circle sliding in from off the leading edge with
/// them. Animating a slot's width instead let each `Text` re-truncate and cross-fade on its own.
private struct RecipientRowSelectReveal: Layout {

    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    /// The circle plus the gap after it: the width the row's content moves right by.
    private static let slot: CGFloat = 22 + 12

    private var offset: CGFloat { Self.slot * progress }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let content = subviews[1].sizeThatFits(
            ProposedViewSize(width: proposal.width.map { max(0, $0 - offset) }, height: proposal.height)
        )
        let circle = subviews[0].sizeThatFits(.unspecified)
        return CGSize(width: offset + content.width, height: max(content.height, circle.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews[0].place(
            at: CGPoint(x: bounds.minX + offset - Self.slot, y: bounds.midY),
            anchor: .leading,
            proposal: .unspecified
        )
        subviews[1].place(
            at: CGPoint(x: bounds.minX + offset, y: bounds.minY),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: max(0, bounds.width - offset), height: bounds.height)
        )
    }
}

/// Select mode's leading circle: the same 22pt outline and filled check as Select People.
private struct RecipientRowSelectCircle: View {

    let isSelected: Bool

    var body: some View {
        // One image whose symbol swaps, so a tap changes the circle in place. Two images in an
        // if/else would be two views, and the tap would swap one for the other instead of the symbol.
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 22))
            // A white check on the unread blue, the selection colour the design uses.
            .symbolRenderingMode(isSelected ? .palette : .monochrome)
            .foregroundStyle(
                isSelected ? Color.textMain : Color.textSecondary,
                Color.unreadIndicator
            )
            .contentTransition(.symbolEffect(.replace))
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
    func recipientRowChrome(accessibilityLabel: String, isSelected: Bool = false) -> some View {
        self
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets(top: 14, leading: 20, bottom: 14, trailing: 20))
            // A picked row in select mode takes the row fill; otherwise rows sit on the screen.
            .listRowBackground(isSelected ? Color.backgroundRow : Color.clear)
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
    /// Off in select mode, where a tap picks the row rather than opening it.
    var showsChevron = true

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
            } else if showsChevron {
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
