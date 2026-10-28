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

/// The thumb's surface with `content` on it: Liquid Glass on iOS 26, a thin material with a
/// hairline on iOS 18. The lens look draws a see-through glass rim while idle.
struct SwipeThumbSurface<Content: View>: View {

    let look: SwipeControlLook
    let isIdle: Bool
    let glassNamespace: Namespace.ID
    @ViewBuilder let content: Content

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        if #available(iOS 26, *) {
            if SwipeMetrics.usesGlass {
                glass
            } else {
                material
            }
        } else {
            material
        }
    }

    private var face: some View {
        content.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @available(iOS 26, *)
    @ViewBuilder
    private var glass: some View {
        switch look {
        case .lens where isIdle:
            face.background { lensRim }
        case .glassThumb, .morphFill, .lens:
            face
                .glassEffect(
                    .regular
                        .tint(.white.opacity(SwipeMetrics.glassTint))
                        .interactive(SwipeMetrics.glassInteractive),
                    in: .capsule
                )
                .glassEffectID(glassID, in: glassNamespace)
        }
    }

    private var material: some View {
        face
            .background(.thinMaterial, in: .capsule)
            .overlay {
                Capsule()
                    .strokeBorder(.white.opacity(SwipeMetrics.fallbackHairline), lineWidth: 1 / displayScale)
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
