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

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var knobX: CGFloat = 0
    @State private var state: KnobState = .normal
    @State private var shakePhase: Double = 0

    private let text: String
    private let action: ThrowingAction
    private let completion: ThrowingAction?

    /// Creates the control with `text` on its track, which callers pass already localized; `action`
    /// runs on commit and `completion` after the success check shows.
    public init(text: String, action: @escaping ThrowingAction, completion: ThrowingAction? = nil) {
        self.text = text
        self.action = action
        self.completion = completion
    }

    public var body: some View {
        GeometryReader { geometry in
            let diameter = geometry.size.height
            // Never narrower than tall, so the resting thumb always covers the track's leading end.
            let thumbWidth = min(max(SwipeMetrics.thumbWidth, diameter), geometry.size.width)
            let maxX = geometry.size.width - thumbWidth

            SwipingTrack(
                text: text,
                diameter: diameter,
                thumbWidth: thumbWidth,
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
            SwipeMetrics.trackFill
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
/// control's background or failure tint. As the thumb advances the label
/// fades toward transparent, bent by the lens wherever the thumb sits.
private struct SwipingTrack: View {

    let text: String
    let diameter: CGFloat
    let thumbWidth: CGFloat
    let maxX: CGFloat
    let knobX: CGFloat
    let state: KnobState
    let onCommit: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @GestureState private var dragOffset: CGFloat? = nil
    @State private var isNudging = false
    @State private var isPressed = false
    // Set on the press spring, outside the drag's animation-disabled transaction.
    @State private var isLifted = false
    // Bumped by a release that doesn't commit; the drag's end alone decides, whatever order the
    // press detector's end arrives in.
    @State private var releaseCount = 0
    @Namespace private var glassNamespace

    var body: some View {
        let isNormal = state == .normal
        let isTouching = dragOffset != nil
        let wantsLift = (isPressed || isTouching) && isNormal && isEnabled
        let position = knobX + (dragOffset ?? 0)
        let nudgeX: CGFloat = (isNormal && isEnabled && dragOffset == nil && isNudging && !reduceMotion) ? SwipeMetrics.nudgeDistance : 0
        let snap = SwipeMetrics.snapBack.animation(reduceMotion: reduceMotion)
        let nudge = SwipeMetrics.nudge.animation(reduceMotion: reduceMotion)
        let press = SwipeMetrics.press.animation(reduceMotion: reduceMotion)

        let labelOpacity = maxX > 0 ? 1 - min(max(position / maxX, 0), 1) : 1
        let liftScale = isLifted && !reduceMotion ? SwipeMetrics.pressScale : 1

        ZStack(alignment: .leading) {
            Text(text)
                .lineLimit(1)
                .minimumScaleFactor(SwipeMetrics.labelMinimumScale)
                .font(.appTextMedium)
                .foregroundStyle(.textMain)
                // Before the lens, so the band bends with the label.
                .modifier(SwipeShimmer(
                    isOn: !reduceMotion,
                    isRunning: isNormal && isEnabled && !isTouching
                ))
                .padding(.horizontal, thumbWidth)
                .frame(maxWidth: .infinity, maxHeight: .infinity) // span the track so the mask and lens are in track coordinates
                .modifier(SwipeLensEffect(
                    centerX: position + nudgeX + thumbWidth / 2,
                    radius: diameter / 2 * liftScale,
                    halfLength: (thumbWidth - diameter) / 2 * liftScale,
                    bend: SwipeMetrics.lensBend,
                    band: SwipeMetrics.lensBand,
                    zoom: SwipeMetrics.lensZoom,
                    falloff: SwipeMetrics.lensFalloff,
                    aberration: SwipeMetrics.lensAberration,
                    isEnabled: SwipeMetrics.usesGlass
                ))
                .animation(snap, value: position)
                .animation(nudge, value: nudgeX)
                .animation(press, value: isLifted)
                .opacity(labelOpacity)
                .opacity(isNormal ? 1 : 0)

            SwipeThumbSurface(isIdle: isNormal, glassNamespace: glassNamespace) {
                thumbIcon
            }
            .animation(press) { $0.scaleEffect(liftScale) }
            .opacity(isLifted && reduceMotion ? SwipeMetrics.pressDim : 1)
            .frame(width: thumbWidth, height: diameter)
            .contentShape(.capsule) // the lens's see-through middle takes the touch too
            .offset(x: position)
            .animation(snap, value: position)
            .offset(x: nudgeX)
            .animation(nudge, value: nudgeX)
            // Sees touch-down even where a sheet holds the drag back until the finger moves.
            .gesture(SwipePressDetector { isPressed = $0 })
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
                        guard SwipeControl.shouldCommit(percent: percent, velocity: velocity) else {
                            releaseCount += 1
                            return
                        }
                        onCommit()
                    }
            )
            .disabled(!isNormal)
            // Reduce Motion swaps the thumb by identity at commit and reset, so the park and
            // the return after a send crossfade rather than travel.
            .id(reduceMotion ? isNormal : true)
            .transition(.opacity)
        }
        .animation(reduceMotion ? .easeInOut(duration: SwipeMetrics.reduceMotionFade) : nil, value: isNormal)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // A probe of its own, so the progress's animation never reaches the label or thumb.
        .background {
            Color.clear
                .modifier(SwipeProgressReporter(progress: maxX > 0 ? min(max(position / maxX, 0), 1) : 0))
                .animation(reduceMotion ? .easeOut(duration: SwipeMetrics.reduceMotionFade) : snap, value: position)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .onChange(of: wantsLift) { _, lift in
            withAnimation(press) { isLifted = lift }
        }
        .sensoryFeedback(SwipeMetrics.pressHaptic, trigger: wantsLift) { wasLifted, lift in
            !wasLifted && lift
        }
        .sensoryFeedback(SwipeMetrics.releaseHaptic, trigger: releaseCount)
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

/// How far a ``SwipeControl``'s thumb has travelled along its track, from 0 at rest to 1 at the end,
/// which it holds through loading, success and failure. Read it with `onPreferenceChange` to drive
/// visuals around the control; it follows the finger while dragging and the thumb's own motion after.
public struct SwipeControlProgressKey: PreferenceKey {
    public static let defaultValue: CGFloat = 0

    public static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Publishes `progress` as ``SwipeControlProgressKey`` on every frame it animates through, so a
/// reader moves on the thumb's spring rather than jumping to the end value.
private struct SwipeProgressReporter: ViewModifier, Animatable {

    var progress: CGFloat

    nonisolated var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content.preference(key: SwipeControlProgressKey.self, value: progress)
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
            SwipeControl(text: "Swipe to Send") {
                try await Task.delay(seconds: 2)
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
