//
//  SwipeControl.swift
//  FlipcashUI
//
//  Created by Raul Riera.
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import FlipcashCore

/// Thrown by a ``SwipeControl`` action when the send went out and didn't go
/// through (a network error, say), so the control plays its failure look before
/// it resets. Any other error resets it silently.
public struct SwipeControlFailure: Error {
    public init() {}
}

/// A slide-to-confirm control. The user drags the knob along the track; once it
/// passes the commit threshold the `action` runs, showing a loading indicator
/// and then a success checkmark before the knob resets. An action that throws
/// ``SwipeControlFailure`` shows a brief failure before the reset; any other
/// error resets it silently.
///
/// The knob commits when dragged past 70% of the track, or past 50% with a fast
/// release velocity.
///
/// ```swift
/// SwipeControl(text: "Swipe to Send") {
///     try await session.send(amount)
/// }
/// ```
public struct SwipeControl: View {

    @Environment(\.displayScale) private var displayScale
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.swipeControlLook) private var lookOverride

    @State private var knobX: CGFloat = 0
    @State private var state: KnobState = .normal
    @State private var shakePhase: Double = 0

    private let text: String
    private let action: ThrowingAction
    private let completion: ThrowingAction?

    public init(text: String, action: @escaping ThrowingAction, completion: ThrowingAction? = nil) {
        self.text = text
        self.action = action
        self.completion = completion
    }

    public var body: some View {
        GeometryReader { geometry in
            let diameter = geometry.size.height
            let maxX = geometry.size.width - diameter

            SwipingTrack(
                text: text,
                look: lookOverride ?? SwipeMetrics.look,
                diameter: diameter,
                maxX: maxX,
                knobX: knobX,
                state: state
            ) {
                // Parks the thumb in the release's own update, so it never springs back first.
                knobX = maxX
                Task { await commit(maxX: maxX) }
            }
        }
        .padding(SwipeMetrics.thumbInset)
        .frame(height: SwipeMetrics.height)
        .background {
            Capsule()
                .fill(trackFill)
                .animation(.easeOut(duration: SwipeMetrics.failureTintFade), value: state == .failure)
        }
        .overlay {
            Capsule()
                .strokeBorder(SwipeMetrics.strokeColor, lineWidth: 1 / displayScale)
        }
        .modifier(SwipeShake(phase: shakePhase, distance: SwipeMetrics.shakeDistance, count: SwipeMetrics.shakeCount))
        .opacity(isEnabled ? 1 : SwipeMetrics.disabledOpacity)
        .sensoryFeedback(.impact(weight: .heavy), trigger: state) { _, newState in newState == .loading }
        .sensoryFeedback(.error, trigger: state) { _, newState in newState == .failure }
        .onChange(of: state) { _, newState in
            if newState == .failure && !reduceMotion {
                withAnimation(.linear(duration: SwipeMetrics.shakeDuration)) {
                    shakePhase += 1
                }
            }
        }
        .accessibilityRepresentation {
            Button(text) {
                Task {
                    do {
                        try await action()
                        try await completion?()
                    } catch {}
                }
            }
        }
    }

    private var trackFill: Color {
        switch state {
        case .failure:
            .bannerError.opacity(SwipeMetrics.failureTint)
        case .normal, .loading, .success:
            .action.opacity(SwipeMetrics.fillOpacity)
        }
    }

    private func commit(maxX: CGFloat) async {
        state = .loading
        knobX = maxX
        do {
            try await action()
        } catch {
            if error is SwipeControlFailure {
                state = .failure
                try? await Task.delay(milliseconds: Int(SwipeMetrics.failureHold * 1000))
            }
            state = .normal
            knobX = 0
            return
        }
        do {
            state = .success
            try await completion?()
            try await Task.delay(seconds: 2)
        } catch {}
        state = .normal
        knobX = 0
    }

    /// Whether a release at `percent` of the track, with the predicted end
    /// `velocity` points ahead of the finger, commits.
    nonisolated static func shouldCommit(percent: CGFloat, velocity: CGFloat) -> Bool {
        percent > Layout.commitFraction
            || (percent > Layout.velocityAssistFraction && velocity > Layout.velocityAssistMinimum)
    }
}

/// Owns the high-frequency drag and idle-nudge state, and renders the label and
/// thumb together so a drag (or nudge) re-renders only the track, not the
/// control's background, border, or failure tint. As the thumb advances it
/// masks the label away from the left and fades the still-visible remainder
/// toward transparent.
private struct SwipingTrack: View {

    let text: String
    let look: SwipeControlLook
    let diameter: CGFloat
    let maxX: CGFloat
    let knobX: CGFloat
    let state: KnobState
    let onCommit: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @GestureState private var dragOffset: CGFloat? = nil
    @State private var isNudging = false
    // Follows the touch one update after the drag's, whose transaction disables animations.
    @State private var isLifted = false
    @Namespace private var glassNamespace

    var body: some View {
        let isNormal = state == .normal
        let isTouching = dragOffset != nil
        let position = knobX + (dragOffset ?? 0)
        let nudgeX: CGFloat = (isNormal && isEnabled && dragOffset == nil && isNudging && !reduceMotion) ? SwipeMetrics.nudgeDistance : 0
        let fills = look == .morphFill && !isNormal
        let snap = SwipeMetrics.snapBack.animation(reduceMotion: reduceMotion)
        let nudge = SwipeMetrics.nudge.animation(reduceMotion: reduceMotion)
        let press = SwipeMetrics.press.animation(reduceMotion: reduceMotion)

        let labelOpacity = (SwipeMetrics.labelFades && maxX > 0) ? 1 - min(max(position / maxX, 0), 1) : 1
        let wipeEdge = look == .lens ? SwipeMetrics.lensWipeEdge : SwipeMetrics.labelWipeEdge
        let wipeX = SwipeMetrics.labelWipes ? position + diameter * wipeEdge : 0
        let liftScale = isLifted && !reduceMotion ? pressScale : 1

        ZStack(alignment: .leading) {
            Text(text)
                .lineLimit(1)
                .minimumScaleFactor(SwipeMetrics.labelMinimumScale)
                .font(.appTextMedium)
                .foregroundStyle(.textMain)
                .padding(.horizontal, diameter)
                .frame(maxWidth: .infinity, maxHeight: .infinity) // span the track so the mask and lens are in track coordinates
                .modifier(SwipeLensEffect(
                    centerX: position + nudgeX + diameter / 2,
                    radius: diameter / 2 * liftScale,
                    bend: SwipeMetrics.lensBend,
                    band: SwipeMetrics.lensBand,
                    isEnabled: look == .lens && SwipeMetrics.usesGlass
                ))
                .animation(snap, value: position)
                .animation(nudge, value: nudgeX)
                .animation(press, value: isLifted)
                .mask(alignment: .leading) {
                    Color.black
                        .opacity(labelOpacity)
                        .offset(x: wipeX)
                        .animation(snap, value: wipeX)
                }
                .opacity(isNormal ? 1 : 0)

            SwipeThumbSurface(look: look, isIdle: isNormal, glassNamespace: glassNamespace) {
                thumbIcon
            }
            .animation(press) { $0.scaleEffect(liftScale) }
            .opacity(isLifted && reduceMotion ? SwipeMetrics.pressDim : 1)
            .frame(width: fills ? maxX + diameter : diameter, height: diameter)
            .contentShape(.capsule) // the lens's see-through middle takes the touch too
            .offset(x: fills ? 0 : position)
            .animation(snap, value: position)
            .animation(SwipeMetrics.morph.animation(reduceMotion: reduceMotion), value: fills)
            .offset(x: nudgeX)
            .animation(nudge, value: nudgeX)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($dragOffset) { value, dragState, transaction in
                        transaction.disablesAnimations = true
                        dragState = min(max(value.translation.width, 0), maxX)
                    }
                    .onEnded { value in
                        let offset = min(max(value.translation.width, 0), maxX)
                        let velocity = value.predictedEndLocation.x - value.location.x
                        let percent = maxX > 0 ? offset / maxX : 0
                        guard SwipeControl.shouldCommit(percent: percent, velocity: velocity) else { return }
                        onCommit()
                    }
            )
            .disabled(!isNormal)
            // Reduce Motion swaps the thumb by identity at commit and reset, so the morph and
            // the return after a send crossfade rather than travel.
            .id(reduceMotion ? isNormal : true)
            .transition(.opacity)
        }
        .animation(reduceMotion ? .easeInOut(duration: SwipeMetrics.reduceMotionFade) : nil, value: isNormal)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: isTouching) { _, touching in
            isLifted = touching
        }
        .sensoryFeedback(.impact(flexibility: .soft, intensity: SwipeMetrics.touchHaptic), trigger: isTouching) { wasTouching, touching in
            !wasTouching && touching
        }
        .task {
            do {
                try await Task.delay(seconds: 3)
                while true {
                    isNudging = true
                    try await Task.delay(milliseconds: 150)
                    isNudging = false
                    try await Task.delay(seconds: 4)
                }
            } catch {
                isNudging = false
            }
        }
    }

    private var pressScale: CGFloat {
        switch look {
        case .glassThumb, .morphFill: SwipeMetrics.pressScale
        case .lens: SwipeMetrics.lensPressScale
        }
    }

    // Every swap between the arrow and the progress snaps.
    private var thumbIcon: some View {
        ZStack {
            switch state {
            case .normal:
                Image.icon(.arrowRight)
                    .iconSize(SwipeMetrics.arrowSize)
                    .foregroundStyle(.textMain)
            case .loading:
                ButtonStateLabel(text, state: .loading)
                    .tint(.textSecondary)
            case .success:
                ButtonStateLabel(text, state: .success)
            case .failure:
                Image.icon(.crossMedium)
                    .iconSize(SwipeMetrics.arrowSize)
                    .foregroundStyle(.textMain)
            }
        }
        .animation(nil, value: state)
    }
}

nonisolated private enum Layout {
    static let commitFraction: CGFloat = 0.7
    static let velocityAssistFraction: CGFloat = 0.5
    static let velocityAssistMinimum: CGFloat = 200
}

private enum KnobState {
    case normal
    case loading
    case success
    case failure
}

#Preview {
    Background(color: .backgroundMain) {
        VStack(spacing: 32) {
            ForEach(SwipeControlLook.allCases, id: \.self) { look in
                SwipeControl(text: "Swipe to Send") {
                    try await Task.delay(seconds: 2)
                }
                .swipeControlLook(look)
            }

            SwipeControl(text: "Swipe to Fail") {
                try await Task.delay(seconds: 1)
                throw SwipeControlFailure()
            }

            SwipeControl(text: "Swipe to Send") {
                try await Task.delay(seconds: 1)
            }
            .disabled(true)
        }
        .padding(20)
    }
}
