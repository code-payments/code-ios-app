//
//  JumpToBottomModel.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import Observation
import SwiftUI
import FlipcashCore

/// What the jump-to-bottom button shows, set by ``ChatScreenViewController`` from the transcript and
/// read by the bar, which draws the button above its trailing control so one transaction moves both.
@MainActor @Observable
public final class JumpToBottomModel {
    /// Whether the reader is off the bottom of a transcript whose opening scroll has landed, or has a
    /// reply origin to go back to.
    public var isVisible = false
    /// Whether something drawn over the transcript (a blur, a spotlighted edit) means the button must
    /// not show, since the bar's view stands above those.
    public var isSuppressed = false
    /// Inbound messages the reader hasn't seen; the badge hides at zero.
    public var unreadCount = 0
    /// Scrolls the transcript to its newest message.
    public var onTap: () -> Void = {}

    public init() {}

    /// Whether the button shows and takes taps.
    public var isShown: Bool { isVisible && !isSuppressed }
}

/// The jump-to-bottom button: a 44pt circle in the composer's glass, with a chevron and an unread badge.
public struct JumpToBottomButtonView: View {

    public static var diameter: CGFloat { Tuner.value("Chat v2 Jump/Size", default: 36, in: 28...64, unit: .points) } // LOCAL-TUNER
    /// The area above the bar's top edge, from its trailing side, that the button and its badge
    /// occupy, with the gap the bar leaves under the button. Touches in it go to the button.
    public static var reach: CGSize { CGSize(width: 88, height: 20 + diameter + 12) } // LOCAL-TUNER
    private static var badgeHeight: CGFloat { Tuner.value("Chat v2 Jump/Badge size", default: 22, in: 14...32, unit: .points) } // LOCAL-TUNER

    public let unreadCount: Int
    public let action: () -> Void

    /// The button's own, so its glass never joins the `$` button's.
    @Namespace private var glassNamespace

    public init(unreadCount: Int, action: @escaping () -> Void) {
        self.unreadCount = unreadCount
        self.action = action
    }

    public var body: some View {
        let badgeText = UnreadBadgeText.text(for: unreadCount)
        Button(action: action) {
            Image.icon(.chevronDownMedium)
                .iconSize(Tuner.value("Chat v2 Jump/Icon size", default: 22, in: 12...32, unit: .points)) // LOCAL-TUNER
                .foregroundStyle(.white)
                .frame(width: Self.diameter, height: Self.diameter)
                .composerGlass(in: Circle(), id: "jump", namespace: glassNamespace)
                .composerRim(in: Circle())
                .contentShape(Circle())
                .overlay(alignment: .topTrailing) {
                    if let badgeText {
                        badge(badgeText)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Jump to latest message")
        .accessibilityValue(badgeText ?? "")
    }

    /// The pill: blue fill, white semibold 11, and a 2pt ring in the chat background that separates it
    /// from the circle. Its centre sits near the circle's top-trailing corner, pulled in along the arc.
    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .frame(minWidth: Self.badgeHeight, minHeight: Self.badgeHeight)
            .background(Color.badgeFocus, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.backgroundMain, lineWidth: 2))
            .alignmentGuide(.trailing) { $0.width / 2 + 4 }
            .alignmentGuide(.top) { _ in Self.badgeHeight / 2 - 4 }
    }
}
#endif
