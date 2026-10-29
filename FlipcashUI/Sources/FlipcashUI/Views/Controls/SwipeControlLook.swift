//
//  SwipeControlLook.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI

// MARK: - Thumb surface

/// The thumb's surface with `content` on it. While idle on iOS 26 it is clear glass over the lens
/// with `content` above it; otherwise the composer's glass (a tinted material before iOS 26).
struct SwipeThumbSurface<Content: View>: View {

    let isIdle: Bool
    let glassNamespace: Namespace.ID
    @ViewBuilder let content: Content

    var body: some View {
        GlassContainer {
            surface
        }
        // Outside the container, which composites its glass above sibling content.
        .overlay {
            if showsLens {
                face
            }
        }
    }

    private var showsLens: Bool {
        isIdle && SwipeMetrics.usesGlass
    }

    private var face: some View {
        content.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var surface: some View {
        if showsLens {
            if #available(iOS 26, *) {
                lensGlass
            }
        } else {
            face.composerGlass(in: Capsule(), id: glassID, namespace: glassNamespace, isInteractive: false)
        }
    }

    /// Clear glass over the lens; it shares an ID with the composer glass so the thumb morphs
    /// between them at commit and reset.
    @available(iOS 26, *)
    private var lensGlass: some View {
        Capsule()
            .fill(.clear)
            .glassEffect(.clear, in: .capsule)
            .glassEffectID(glassID, in: glassNamespace)
    }

    private var glassID: String { "thumb" }
}

// MARK: - Effects

/// Bends the content under a capsule at `centerX` with end-cap `radius` and a straight run of
/// `halfLength` either side (a circle at 0), through the `swipeLens` shader.
struct SwipeLensEffect: ViewModifier, Animatable {

    var centerX: CGFloat
    var radius: CGFloat
    var halfLength: CGFloat
    let bend: CGFloat
    let band: CGFloat
    let zoom: CGFloat
    let falloff: CGFloat
    let aberration: CGFloat
    let isEnabled: Bool

    nonisolated var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(centerX, AnimatablePair(radius, halfLength)) }
        set {
            centerX = newValue.first
            radius = newValue.second.first
            halfLength = newValue.second.second
        }
    }

    func body(content: Content) -> some View {
        content.layerEffect(
            ShaderLibrary.bundle(.module).swipeLens(
                .boundingRect,
                .float(centerX),
                .float(radius),
                .float(max(halfLength, 0)),
                .float(bend),
                .float(radius * band),
                .float(max(zoom, 0.01)),
                .float(falloff),
                .float(aberration)
            ),
            maxSampleOffset: CGSize(width: bend + aberration + (radius + halfLength) * (1 - 1 / max(zoom, 1)), height: bend + aberration + radius),
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
                        .opacity(isRunning ? 1 : 0)
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
            let period = SwipeMetrics.shimmerPeriod

            // Driven by the clock, so a body pass never restarts the sweep.
            TimelineView(.animation(paused: !isRunning)) { context in
                let elapsed = context.date.timeIntervalSinceReferenceDate
                let progress = elapsed.truncatingRemainder(dividingBy: period) / period

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
