//
//  TrayAction.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI

/// One of a tray's capsule buttons: its title, its weight, its progress, and what it does.
///
/// A tray holds one or two, side by side with the secondary on the left. The right-hand action
/// keeps its place across a flow's steps, and a change of title crossfades in place.
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

/// A tray's actions side by side at equal widths, the secondary on the left.
struct TrayActionBar: View {

    let actions: [TrayAction]

    /// Whether the flow last moved forward; a step back reverses the title's rise.
    var movesForward = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: TrayMetrics.actionGap) {
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
            ButtonStateLabel(action.title, state: action.state)
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
