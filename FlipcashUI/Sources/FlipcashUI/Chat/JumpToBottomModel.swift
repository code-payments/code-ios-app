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

/// The jump-to-bottom button: a 36pt circle in the composer's glass, with a chevron and an unread badge.
public struct JumpToBottomButtonView: View {

    public static let diameter: CGFloat = 36
    /// The button's hit area, a 44pt circle around the smaller drawn one.
    public static let hitDiameter: CGFloat = 44
    /// How far the hit area reaches past the drawn circle on each side.
    public static let hitOutset: CGFloat = (hitDiameter - diameter) / 2
    /// The area above the bar's top edge, from its trailing side, that the button and its badge
    /// occupy, with the gap the bar leaves under the button. Touches in it go to the button.
    public static let reach = CGSize(width: 88, height: 20 + diameter + 12)
    private static let badgeHeight: CGFloat = 22

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
                .iconSize(22)
                .foregroundStyle(.white)
                .frame(width: Self.diameter, height: Self.diameter)
                .composerGlass(in: Circle(), id: "jump", namespace: glassNamespace)
                .composerRim(in: Circle())
                .overlay(alignment: .topTrailing) {
                    if let badgeText {
                        badge(badgeText)
                    }
                }
                .frame(width: Self.hitDiameter, height: Self.hitDiameter)
                .contentShape(Circle())
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
