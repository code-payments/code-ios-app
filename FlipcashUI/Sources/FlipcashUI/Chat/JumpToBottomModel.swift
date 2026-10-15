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
    /// Whether the reader is off the bottom of a transcript whose opening scroll has landed.
    public var isVisible = false
    /// Whether something drawn over the transcript (a blur, a spotlighted edit) means the button must
    /// not show, since the bar's view stands above those.
    public var isSuppressed = false
    /// Inbound messages the reader hasn't seen; the badge hides at zero.
    public var unreadCount = 0
    /// Scrolls the transcript to its newest message.
    public var onTap: () -> Void = {}

    public init() {}

    /// Where the button stands, in window coordinates, as the bar last laid it out.
    public var buttonFrame: CGRect = .zero

    /// Whether the button shows and takes taps.
    public var isShown: Bool { isVisible && !isSuppressed }

    /// Whether a touch at `point`, in window coordinates, lands on the visible button: its circle, or
    /// the badge overhanging its top-trailing corner. Nothing else near the button counts.
    public func hitsButton(at point: CGPoint) -> Bool {
        guard isShown, !buttonFrame.isEmpty else { return false }
        let radius = buttonFrame.width / 2
        let centre = CGPoint(x: buttonFrame.midX, y: buttonFrame.midY)
        if hypot(point.x - centre.x, point.y - centre.y) <= radius { return true }
        guard unreadCount > 0 else { return false }
        let inset = JumpToBottomButtonView.badgeInset
        let badgeCentre = CGPoint(x: buttonFrame.maxX - inset, y: buttonFrame.minY + inset)
        let badge = CGRect(x: badgeCentre.x - 15, y: badgeCentre.y - 11, width: 30, height: 22)
        return badge.contains(point)
    }
}

/// The jump-to-bottom button: a 44pt circle in the composer's glass, with a chevron and an unread badge.
public struct JumpToBottomButtonView: View {

    public static let diameter: CGFloat = 44
    /// The area above the bar's top edge, from its trailing side, that the button and its badge
    /// occupy, with room to spare for the gap the bar leaves under it. The bar's clip leaves it
    /// uncut and lets touches in it through to the button.
    public static let reach = CGSize(width: 88, height: 20 + diameter + 12)
    private static let badgeHeight: CGFloat = 22

    /// How far the badge's centre stands inside the circle's bounding square, from the top and the
    /// trailing edge: where a 45 degree radius meets the arc, r(1 - 1/sqrt 2). Android's value.
    public static let badgeInset: CGFloat = diameter / 2 * (1 - 1 / 2.0.squareRoot())

    public let unreadCount: Int
    public let action: () -> Void

    /// The button's own, so its glass never joins the `$` button's.
    @Namespace private var glassNamespace

    /// Advances when another message lands under a badge that is already up, to play the bump.
    @State private var bumpTick = 0

    public init(unreadCount: Int, action: @escaping () -> Void) {
        self.unreadCount = unreadCount
        self.action = action
    }

    public var body: some View {
        let badgeText = UnreadBadgeText.text(for: unreadCount)
        Button(action: action) {
            Image(systemName: "chevron.down")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: Self.diameter, height: Self.diameter)
                .composerGlass(in: Circle(), id: "jump", namespace: glassNamespace)
                .composerRim(in: Circle())
                .contentShape(Circle())
                .overlay(alignment: .topTrailing) {
                    if let badgeText {
                        badge(badgeText)
                            .keyframeAnimator(initialValue: CGFloat(1), trigger: bumpTick) { content, scale in
                                content.scaleEffect(scale)
                            } keyframes: { _ in
                                SpringKeyframe(ChatMotion.jumpBadgeBumpPeak, duration: 0.08, spring: Spring(duration: ChatMotion.jumpBadgeBump.duration, bounce: ChatMotion.jumpBadgeBump.bounce))
                                SpringKeyframe(1, duration: 0.3, spring: Spring(duration: ChatMotion.jumpBadgeBump.duration, bounce: ChatMotion.jumpBadgeBump.bounce))
                            }
                            .transition(.scale.combined(with: .opacity))
                            // The overlay centres the pill's corner on the circle's: nudge it out to the arc.
                            .offset(x: Self.badgeHeight / 2 - Self.badgeInset, y: Self.badgeInset - Self.badgeHeight / 2)
                    }
                }
                .animation(ChatMotion.jumpBadgeEnter.animation.delay(ChatMotion.jumpBadgeDelay), value: badgeText == nil)
        }
        .buttonStyle(.plain)
        .onChange(of: unreadCount) { old, new in
            if old > 0, new > old { bumpTick += 1 }
        }
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

    }
}
#endif
