//
//  SwipeControlLook.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI

/// The ways ``SwipeControl`` can look; they share the track, the drag and every behaviour, and differ
/// in the thumb and in how a commit plays.
public enum SwipeControlLook: String, CaseIterable {
    /// A glass thumb that parks at the end on commit and shows the progress in place.
    case glassThumb
    /// The glass thumb, which grows to fill the track on commit and shows the progress centred.
    case morphFill
    /// A see-through glass rim that bends the label as it passes; commits as `glassThumb` does.
    case lens
}

extension SwipeControlLook: TunableEnum {} // LOCAL-TUNER: conformance

extension EnvironmentValues {
    /// The look ``SwipeControl`` takes, or `nil` for the tuner's pick.
    @Entry var swipeControlLook: SwipeControlLook? = nil
}

public extension View {
    /// Sets the look of every ``SwipeControl`` in this view; `nil` leaves the default.
    func swipeControlLook(_ look: SwipeControlLook?) -> some View {
        environment(\.swipeControlLook, look)
    }
}

// MARK: - Thumb surfaces

/// The thumb's surface with `content` on it: the composer's glass (a tinted material before
/// iOS 26). The lens look draws a see-through glass rim while idle, with `content` above it.
struct SwipeThumbSurface<Content: View>: View {

    let look: SwipeControlLook
    let isIdle: Bool
    let glassNamespace: Namespace.ID
    @ViewBuilder let content: Content

    var body: some View {
        GlassContainer {
            surface
        }
        // Outside the container, which composites its glass above sibling content.
        .overlay {
            if showsRim {
                face
            }
        }
    }

    private var showsRim: Bool {
        look == .lens && isIdle && SwipeMetrics.usesGlass
    }

    private var face: some View {
        content.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var surface: some View {
        if SwipeMetrics.forcesFallback { // LOCAL-TUNER: draws `composerGlass`'s iOS 18 branch on iOS 26
            face
                .background(Color.white.opacity(0.03), in: .capsule) // LOCAL-TUNER
                .background(.ultraThinMaterial, in: .capsule) // LOCAL-TUNER
        } else if showsRim {
            if #available(iOS 26, *) {
                lensRim
            }
        } else {
            face.composerGlass(in: Capsule(), id: glassID, namespace: glassNamespace, isInteractive: SwipeMetrics.glassInteractive)
        }
    }

    /// Clear glass masked to a soft ring, so the label reads through the middle.
    @available(iOS 26, *)
    private var lensRim: some View {
        Circle()
            .fill(.clear)
            .glassEffect(.clear.tint(.white.opacity(SwipeMetrics.lensRimTint)), in: .circle)
            .glassEffectID(glassID, in: glassNamespace)
            .mask {
                Circle()
                    .strokeBorder(.black, lineWidth: SwipeMetrics.lensRimWidth)
                    .blur(radius: SwipeMetrics.lensRimSoftness)
            }
    }

    private var glassID: String { "thumb" }
}

// MARK: - Effects

/// Bends the content under a circle at `centerX` with `radius`, through the `swipeLens` shader.
struct SwipeLensEffect: ViewModifier, Animatable {

    var centerX: CGFloat
    var radius: CGFloat
    let bend: CGFloat
    let band: CGFloat
    let isEnabled: Bool

    nonisolated var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(centerX, radius) }
        set {
            centerX = newValue.first
            radius = newValue.second
        }
    }

    func body(content: Content) -> some View {
        content.layerEffect(
            ShaderLibrary.bundle(.module).swipeLens(
                .boundingRect,
                .float(centerX),
                .float(radius),
                .float(bend),
                .float(radius * band)
            ),
            maxSampleOffset: CGSize(width: bend, height: bend),
            isEnabled: isEnabled
        )
    }
}

/// Dims the content and sweeps a bright, tilted band across it on a loop. The band runs while
/// `isRunning`, and pauses and fades away otherwise; with `isOn` off the content is left as is.
struct SwipeShimmer: ViewModifier {

    let isOn: Bool
    let isRunning: Bool

    func body(content: Content) -> some View {
        if isOn {
            content
                .opacity(SwipeMetrics.shimmerLabelOpacity)
                .overlay {
                    content
                        .mask(alignment: .leading) { band }
                        .opacity(isRunning ? SwipeMetrics.shimmerBandOpacity : 0)
                        .animation(.easeOut(duration: SwipeMetrics.shimmerFade), value: isRunning)
                }
        } else {
            content
        }
    }

    private var band: some View {
        GeometryReader { proxy in
            let width = SwipeMetrics.shimmerBandWidth
            let travel = proxy.size.width + width * 2
            let period = SwipeMetrics.shimmerScalesWithLabel ? SwipeMetrics.shimmerPeriod : travel / SwipeMetrics.shimmerSpeed

            // Driven by the clock, so a body pass never restarts the sweep.
            TimelineView(.animation(paused: !isRunning)) { context in
                let elapsed = context.date.timeIntervalSinceReferenceDate
                let progress = period > 0 ? elapsed.truncatingRemainder(dividingBy: period) / period : 0

                Rectangle()
                    .frame(width: width)
                    .blur(radius: SwipeMetrics.shimmerBlur)
                    .rotationEffect(.degrees(SwipeMetrics.shimmerAngle))
                    .offset(x: travel * progress - width)
            }
        }
    }
}

/// A decaying side-to-side shake: each whole step of `phase` plays `count` swings of `distance`.
struct SwipeShake: GeometryEffect {

    var phase: Double
    let distance: CGFloat
    let count: Int

    nonisolated var animatableData: Double {
        get { phase }
        set { phase = newValue }
    }

    nonisolated func effectValue(size: CGSize) -> ProjectionTransform {
        let progress = phase - phase.rounded(.down)
        let swing = sin(progress * Double(count) * 2 * .pi) * (1 - progress)
        return ProjectionTransform(CGAffineTransform(translationX: distance * swing, y: 0))
    }
}
