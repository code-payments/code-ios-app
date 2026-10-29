//
//  TrayAction.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI

/// One of a tray's capsule buttons: its title, its weight, its progress, and what it does.
///
/// A tray holds one or two, side by side with the secondary on the left, or stacked with the
/// primary on top when a title wouldn't fit whole in its half. The right-hand action keeps its
/// place across a flow's steps, and a change of title crossfades in place.
public struct TrayAction {

    /// How an action is weighted against the other action in its tray.
    public enum Role: Hashable, Sendable {
        /// The white capsule on the right: the action the tray exists for.
        case primary
        /// The quiet capsule on the left: the alternative, such as declining.
        case secondary
        /// The primary's place in a solid red capsule: an action that can't be undone.
        case destructive
    }

    let title: String
    let role: Role
    let state: ButtonState
    let isEnabled: Bool
    let action: () -> Void

    /// Creates an action; `state` shows progress through ``ButtonStateLabel`` and disables the
    /// action while it is not `.normal`.
    public init(
        _ title: String,
        role: Role = .primary,
        state: ButtonState = .normal,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.role = role
        self.state = state
        self.isEnabled = isEnabled
        self.action = action
    }

    /// The action's place in the bar, left to right; the primary and the destructive share one,
    /// so a step that swaps them keeps the same capsule.
    var slot: Int {
        switch role {
        case .secondary: 0
        case .primary, .destructive: 1
        }
    }

    /// Whether the action takes taps: enabled, and not showing progress.
    var isInteractive: Bool {
        isEnabled && state.isNormal
    }

    /// `actions` in the bar's left-to-right order.
    static func ordered(_ actions: [TrayAction]) -> [TrayAction] {
        actions.sorted { $0.slot < $1.slot }
    }
}

/// A tray's actions side by side at equal widths, the secondary on the left, or stacked full
/// width, the primary on top, when a title wouldn't fit whole beside the other.
struct TrayActionBar: View {

    let actions: [TrayAction]

    /// Whether the flow last moved forward; a step back reverses the title's rise.
    var movesForward = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TrayActionLayout(spacing: TrayMetrics.actionGap) {
            ForEach(TrayAction.ordered(actions), id: \.slot) { action in
                Button(action: action.action) {
                    label(for: action)
                }
                .buttonStyle(TrayButtonStyle(role: action.role))
                .disabled(!action.isInteractive)
                .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private func label(for action: TrayAction) -> some View {
        switch action.state {
        case .normal:
            ZStack {
                Text(action.title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .id(action.title)
                    .transition(titleTransition)
            }
        case .loading, .success, .successText:
            ZStack {
                // Keeps the title's width, so progress doesn't unstack a bar the title stacked.
                Text(action.title)
                    .lineLimit(1)
                    .hidden()
                    .accessibilityHidden(true)
                ButtonStateLabel(action.title, state: action.state)
            }
        }
    }

    // Old and new titles overlap in place: the old clears while the new lands in the same spot, so
    // the capsule never reads as empty.
    private var titleTransition: AnyTransition {
        let moves = !reduceMotion
        let sign: CGFloat = (movesForward || !TrayMotion.labelFollowsDirection) ? 1 : -1
        let rise = moves ? TrayMotion.labelRise * sign : 0
        let blur = moves ? TrayMotion.labelBlur : 0
        let scale = moves ? TrayMotion.labelScale : 1
        return .trayFade(
            insertion: TrayFade(opacity: 0, blur: blur, scale: scale, offset: rise),
            insertionAnimation: TrayMotion.labelIn.animation.delay(TrayMotion.labelInDelay),
            removal: TrayFade(opacity: 0, blur: blur, scale: scale, offset: -rise),
            removalAnimation: TrayMotion.labelOut.animation
        )
    }
}

/// Lays the bar's buttons, given left to right, side by side at equal widths when every one fits
/// whole in its share, and otherwise stacked full width with the last, the primary, on top.
private struct TrayActionLayout: Layout {

    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? sideBySideWidth(subviews)
        if fitsSideBySide(subviews, in: width) {
            let share = self.share(of: width, among: subviews)
            let height = subviews.map { $0.sizeThatFits(ProposedViewSize(width: share, height: nil)).height }.max() ?? 0
            return CGSize(width: width, height: height)
        }
        let heights = subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }
        return CGSize(width: width, height: heights.reduce(0, +) + gaps(subviews))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        if fitsSideBySide(subviews, in: bounds.width) {
            let share = self.share(of: bounds.width, among: subviews)
            var x = bounds.minX
            for subview in subviews {
                subview.place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(width: share, height: bounds.height))
                x += share + spacing
            }
        } else {
            var y = bounds.minY
            for subview in subviews.reversed() {
                let height = subview.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil)).height
                subview.place(at: CGPoint(x: bounds.minX, y: y), proposal: ProposedViewSize(width: bounds.width, height: height))
                y += height + spacing
            }
        }
    }

    /// The width that keeps every title whole at equal shares: the widest button's ideal width
    /// for each.
    private func sideBySideWidth(_ subviews: Subviews) -> CGFloat {
        let widest = subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        return widest * CGFloat(subviews.count) + gaps(subviews)
    }

    private func fitsSideBySide(_ subviews: Subviews, in width: CGFloat) -> Bool {
        sideBySideWidth(subviews) <= width
    }

    private func share(of width: CGFloat, among subviews: Subviews) -> CGFloat {
        (width - gaps(subviews)) / CGFloat(subviews.count)
    }

    private func gaps(_ subviews: Subviews) -> CGFloat {
        spacing * CGFloat(max(subviews.count - 1, 0))
    }
}

/// The tray's capsule: white with a dark label for the primary, solid red with a white label for
/// the destructive, and a 10% white wash for the secondary.
struct TrayButtonStyle: ButtonStyle {

    let role: TrayAction.Role

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func makeBody(configuration: Configuration) -> some View {
        let press = TrayMetrics.actionPress.resolved(reduceMotion: reduceMotion)
        let isPressed = configuration.isPressed
        return configuration.label
            // SF Pro until type tokens are decided (Phase 2).
            .font(.system(size: TrayMetrics.scaled(TrayMetrics.actionSize, .callout, dynamicTypeSize), weight: .semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: TrayMetrics.actionHeight)
            .background(fill, in: Capsule())
            .contentShape(Capsule())
            .scaleEffect(press == .scale && isPressed ? TrayMetrics.actionPressScale : 1)
            .opacity(press == .dim && isPressed ? TrayMetrics.actionPressDim : 1)
            .animation(.spring(duration: 0.2, bounce: 0), value: isPressed)
    }

    private var foreground: Color {
        guard isEnabled else { return .textMain.opacity(0.2) }
        switch role {
        case .primary: return .textAction
        case .destructive, .secondary: return .textMain
        }
    }

    private var fill: Color {
        switch role {
        case .primary: isEnabled ? .action : .action.opacity(0.1)
        case .destructive: isEnabled ? .bannerError : .bannerError.opacity(0.1)
        // White 10% from the mockup; there is no raised-fill token yet.
        case .secondary: .white.opacity(0.1)
        }
    }
}
