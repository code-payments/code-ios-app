//
//  SwipeMetrics.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI

/// The swipe control's look and feel values: the track, the lens thumb, the shimmer, the failure
/// beat, the haptics and every spring they move on.
///
/// The commit thresholds are not here: they are behaviour, and stay in `SwipeControl`.
@MainActor
enum SwipeMetrics {

    // MARK: - Glass

    /// Whether the thumb is Liquid Glass with the lens; before iOS 26 it is a material thumb.
    static var usesGlass: Bool {
        if #available(iOS 26, *) {
            true
        } else {
            false
        }
    }

    // MARK: - Track

    /// The capsule's height, which stands taller than the tray's capsule buttons.
    static let height: CGFloat = 64
    /// The gap between the thumb and the track's edge.
    static let thumbInset: CGFloat = 4
    /// The thumb's width; wider than the track is tall, so the thumb is a capsule.
    static let thumbWidth: CGFloat = 84
    /// The thumb's arrow and failure cross.
    static let arrowSize: CGFloat = 26
    /// The track's faint `action` wash.
    static let trackFill: Color = .action.opacity(0.075)
    /// The whole control's opacity while disabled.
    static let disabledOpacity: Double = 0.4

    // MARK: - Label

    /// How far the label may shrink to fit one line at large Dynamic Type sizes.
    static let labelMinimumScale: CGFloat = 0.7

    // MARK: - Thumb

    /// How far the idle nudge pushes the thumb right.
    static let nudgeDistance: CGFloat = 16
    /// The thumb's scale under the finger, which lets the lens swell past the track's edge.
    static let pressScale: CGFloat = 1.3
    /// The thumb's opacity under the finger with Reduce Motion on, standing in for the scale.
    static let pressDim: Double = 0.8

    // MARK: - Motion

    /// The thumb settling: snapping back from a short drag, parking at the end, returning after a send.
    static let snapBack = ChatSpring(duration: 0.4, bounce: 0)
    /// The thumb lifting under the finger and settling on release.
    static let press = ChatSpring(duration: 0.3, bounce: 0.25)
    /// The idle nudge's push and return.
    static let nudge = ChatSpring(duration: 0.25, bounce: 0)
    /// With Reduce Motion on, the crossfade that replaces the thumb's travel at commit and reset.
    static let reduceMotionFade: TimeInterval = 0.2

    // MARK: - Lens

    /// How far the lens pulls the label at the rim.
    static let lensBend: CGFloat = 10
    /// How deep inside the rim the bend reaches, as a share of the lens's radius.
    static let lensBand: CGFloat = 0.34
    /// How much the label is magnified inside the lens; 1 leaves it at size.
    static let lensZoom: CGFloat = 1.19
    /// How sharply the bend falls off from the rim; higher keeps the distortion tighter to the edge.
    static let lensFalloff: CGFloat = 1.4
    /// How far apart red and blue split where the lens bends, in points.
    static let lensAberration: CGFloat = 1.3

    // MARK: - Haptic

    /// The tap at touch-down.
    static let pressHaptic: SensoryFeedback = .impact(flexibility: .soft, intensity: 1)
    /// The tap when the finger lifts without committing.
    static let releaseHaptic: SensoryFeedback = .impact(flexibility: .rigid, intensity: 0.175)

    // MARK: - Shimmer

    /// The bright band's width before its blur.
    static let shimmerBandWidth: CGFloat = 30
    /// The band's tilt, in degrees.
    static let shimmerAngle: Double = 15
    /// The band's blur radius, which softens its edges.
    static let shimmerBlur: CGFloat = 5
    /// The label's opacity outside the band, which leaves the band room to read brighter.
    static let shimmerLabelOpacity: Double = 0.6
    /// The time one sweep takes whatever the label's length, so longer labels sweep faster, as GSConfirm does.
    static let shimmerPeriod: TimeInterval = 2.75
    /// The band fading away when the sweep pauses, and back when it resumes.
    static let shimmerFade: TimeInterval = 0.2

    // MARK: - Failure

    /// How far the failure shake swings either side.
    static let shakeDistance: CGFloat = 8
    /// How many swings the failure shake plays.
    static let shakeCount = 3
    /// How long the whole failure shake takes.
    static let shakeDuration: TimeInterval = 0.4
    /// The `bannerError` wash the track takes while it shows the failure.
    static let failureTint: Double = 0.35
    /// The failure tint fading in and out.
    static let failureTintFade: TimeInterval = 0.15
    /// How long the failure shows before the control resets.
    static let failureHold: TimeInterval = 0.6
}

extension ChatSpring {
    /// This spring as an animation, with its bounce removed when Reduce Motion is on.
    func animation(reduceMotion: Bool) -> Animation {
        reduceMotion ? .spring(duration: duration, bounce: 0) : animation
    }
}
