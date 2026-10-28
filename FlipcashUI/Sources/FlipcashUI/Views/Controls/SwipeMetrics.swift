//
//  SwipeMetrics.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI

/// The swipe control's look and feel values: the track, the thumb, the lens, the failure beat and
/// every spring they move on.
///
/// Every value is live in the tuner during the feel round and bakes back to a constant once a look
/// is picked. The commit thresholds are not here: they are behaviour, and stay in `SwipeControl`.
@MainActor
enum SwipeMetrics {

    // MARK: - Look

    /// The look every ``SwipeControl`` takes unless a view sets one with `swipeControlLook(_:)`.
    static var look: SwipeControlLook { Tuner.shared.value("Swipe/Look", default: SwipeControlLook.lens) } // LOCAL-TUNER

    /// Draws the iOS 18 material thumb on iOS 26 too, so the fallback can be judged on a new phone.
    static var forcesFallback: Bool { Tuner.shared.value("Swipe/iOS 18 fallback", default: false) } // LOCAL-TUNER

    /// Whether the thumb is Liquid Glass: iOS 26, and the fallback isn't being forced.
    static var usesGlass: Bool {
        if #available(iOS 26, *) {
            !forcesFallback
        } else {
            false
        }
    }

    // MARK: - Track

    /// The capsule's height, which stands taller than the tray's capsule buttons.
    static var height: CGFloat { layout("Height", 64, 36...80) } // LOCAL-TUNER
    static var thumbInset: CGFloat { layout("Thumb inset", 4, 0...12) } // LOCAL-TUNER
    /// The thumb's width; 0 matches its height for a round thumb, and anything wider makes it a capsule.
    static var thumbWidth: CGFloat { layout("Thumb width", 84, 0...160) } // LOCAL-TUNER
    static var arrowSize: CGFloat { layout("Arrow size", 26, 12...32) } // LOCAL-TUNER
    /// The track's wash colour, before `fillOpacity` applies.
    static var trackColor: Color { Tuner.shared.value("Swipe Layout/Track color", default: Color.action.opacity(0.75), source: ".action.opacity(0.75)") } // LOCAL-TUNER
    /// The track's `action` wash, as today's control draws it.
    static var fillOpacity: Double { Tuner.shared.value("Swipe Layout/Fill opacity", default: 0.1, in: 0...0.3) } // LOCAL-TUNER
    /// The track's hairline, the input field's resting stroke.
    static var strokeColor: Color { Tuner.shared.value("Swipe Layout/Stroke", default: Metrics.inputFieldStrokeColor(highlighted: false), source: "Metrics.inputFieldStrokeColor(highlighted: false)") } // LOCAL-TUNER
    /// Whether the track draws its hairline.
    static var showsTrackStroke: Bool { Tuner.shared.value("Swipe Layout/Track stroke", default: false) } // LOCAL-TUNER
    static var disabledOpacity: Double { Tuner.shared.value("Swipe Layout/Disabled opacity", default: 0.4, in: 0...1) } // LOCAL-TUNER

    // MARK: - Label

    /// How far the label may shrink to fit one line at large Dynamic Type sizes.
    static var labelMinimumScale: CGFloat { Tuner.shared.value("Swipe Layout/Label min scale", default: 0.7, in: 0.5...1) } // LOCAL-TUNER
    /// Whether the label is wiped away from the left as the thumb passes.
    static var labelWipes: Bool { Tuner.shared.value("Swipe Layout/Label wipes", default: false) } // LOCAL-TUNER
    /// Where across the thumb the wipe's edge sits, from its leading edge (0) to its trailing edge (1).
    static var labelWipeEdge: CGFloat { Tuner.shared.value("Swipe Layout/Wipe edge", default: 0.29, in: 0...1) } // LOCAL-TUNER
    /// Whether what's left of the label fades as the thumb travels.
    static var labelFades: Bool { Tuner.shared.value("Swipe Layout/Label fades", default: true) } // LOCAL-TUNER

    // MARK: - Thumb

    /// Whether the thumb's glass also swells under the finger, on top of the press scale.
    static var glassInteractive: Bool { Tuner.shared.value("Swipe Layout/Glass interactive", default: false) } // LOCAL-TUNER
    /// How far the idle nudge pushes the thumb right.
    static var nudgeDistance: CGFloat { layout("Nudge distance", 16, 0...40) } // LOCAL-TUNER

    // MARK: - Press

    /// The thumb's scale under the finger, for the glass thumb and the morph.
    static var pressScale: CGFloat { Tuner.shared.value("Swipe Motion/Press scale", default: 1.06, in: 1...1.3, unit: .multiplier) } // LOCAL-TUNER
    /// The thumb's opacity under the finger with Reduce Motion on, standing in for the scale.
    static var pressDim: Double { Tuner.shared.value("Swipe Motion/Press dim", default: 0.8, in: 0.3...1) } // LOCAL-TUNER

    // MARK: - Motion

    /// The thumb settling: snapping back from a short drag, parking at the end, returning after a send.
    static var snapBack: ChatSpring { spring("Swipe Motion/Snap back", 0.4, 0) } // LOCAL-TUNER
    /// The thumb growing to fill the track on commit, in the morph look.
    static var morph: ChatSpring { spring("Swipe Motion/Morph", 0.4, 0) } // LOCAL-TUNER
    /// The thumb lifting under the finger and settling on release.
    static var press: ChatSpring { spring("Swipe Motion/Press", 0.3, 0.25) } // LOCAL-TUNER
    /// The idle nudge's push and return.
    static var nudge: ChatSpring { spring("Swipe Motion/Nudge", 0.25, 0) } // LOCAL-TUNER
    /// With Reduce Motion on, the crossfade that replaces the morph and the thumb's return after a send.
    static var reduceMotionFade: TimeInterval { Tuner.shared.value("Swipe Motion/Reduce Motion fade", default: 0.2, in: 0...0.5, unit: .seconds) } // LOCAL-TUNER

    // MARK: - Lens

    /// The lens thumb's scale under the finger, which lets it swell past the track's edge.
    static var lensPressScale: CGFloat { Tuner.shared.value("Swipe Lens/Press scale", default: 1.3, in: 1...1.6, unit: .multiplier) } // LOCAL-TUNER
    static var lensRimWidth: CGFloat { Tuner.shared.value("Swipe Lens/Rim width", default: 0.5, in: 0...8, unit: .points) } // LOCAL-TUNER
    static var lensRimSoftness: CGFloat { Tuner.shared.value("Swipe Lens/Rim softness", default: 0, in: 0...6, unit: .points) } // LOCAL-TUNER
    static var lensRimTint: Double { Tuner.shared.value("Swipe Lens/Rim tint", default: 0, in: 0...0.5) } // LOCAL-TUNER
    /// How far the lens pulls the label at the rim.
    static var lensBend: CGFloat { Tuner.shared.value("Swipe Lens/Bend", default: 6.1, in: 0...30, unit: .points) } // LOCAL-TUNER
    /// How deep inside the rim the bend reaches, as a share of the lens's radius.
    static var lensBand: CGFloat { Tuner.shared.value("Swipe Lens/Band", default: 0.73, in: 0.05...1) } // LOCAL-TUNER
    /// The glass the lens rim is made of.
    static var lensGlass: SwipeLensGlass { Tuner.shared.value("Swipe Lens/Glass", default: SwipeLensGlass.clear) } // LOCAL-TUNER
    /// How much the label is magnified inside the lens; 1 leaves it at size.
    static var lensZoom: CGFloat { Tuner.shared.value("Swipe Lens/Zoom", default: 1, in: 1...1.6, unit: .multiplier) } // LOCAL-TUNER
    /// How sharply the bend falls off from the rim; higher keeps the distortion tighter to the edge.
    static var lensFalloff: CGFloat { Tuner.shared.value("Swipe Lens/Falloff", default: 2, in: 0.5...8) } // LOCAL-TUNER
    /// How far apart red and blue split where the lens bends, in points; 0 is none.
    static var lensAberration: CGFloat { Tuner.shared.value("Swipe Lens/Aberration", default: 0, in: 0...4, unit: .points) } // LOCAL-TUNER
    /// The wipe's edge for the lens look, which shows the label through the thumb.
    static var lensWipeEdge: CGFloat { Tuner.shared.value("Swipe Lens/Wipe edge", default: 0.42, in: 0...1) } // LOCAL-TUNER

    // MARK: - Haptic

    /// Whether the thumb taps at touch-down.
    static var hapticOn: Bool { Tuner.shared.value("Swipe Haptic/On", default: true) } // LOCAL-TUNER
    static var hapticStyle: SwipeHapticStyle { Tuner.shared.value("Swipe Haptic/Style", default: SwipeHapticStyle.impactSoft) } // LOCAL-TUNER
    /// The touch-down tap's strength, for the styles that take one.
    static var hapticIntensity: Double { Tuner.shared.value("Swipe Haptic/Intensity", default: 0.5, in: 0...1) } // LOCAL-TUNER
    /// Whether a second tap plays when the finger lifts without committing.
    static var releaseHapticOn: Bool { Tuner.shared.value("Swipe Haptic/On release", default: false) } // LOCAL-TUNER
    static var releaseHapticStyle: SwipeHapticStyle { Tuner.shared.value("Swipe Haptic/Release style", default: SwipeHapticStyle.impactSoft) } // LOCAL-TUNER
    static var releaseHapticIntensity: Double { Tuner.shared.value("Swipe Haptic/Release intensity", default: 0.5, in: 0...1) } // LOCAL-TUNER

    // MARK: - Shimmer

    /// Whether a bright band sweeps the label while the control waits for a swipe.
    static var shimmers: Bool { Tuner.shared.value("Swipe Shimmer/On", default: true) } // LOCAL-TUNER
    static var shimmerBandWidth: CGFloat { Tuner.shared.value("Swipe Shimmer/Band width", default: 30, in: 4...120, unit: .points) } // LOCAL-TUNER
    static var shimmerAngle: Double { Tuner.shared.value("Swipe Shimmer/Angle", default: 15, in: -60...60, unit: .degrees) } // LOCAL-TUNER
    static var shimmerBlur: CGFloat { Tuner.shared.value("Swipe Shimmer/Blur", default: 5, in: 0...20, unit: .points) } // LOCAL-TUNER
    /// The band's opacity: how bright the label reads where the band passes.
    static var shimmerBandOpacity: Double { Tuner.shared.value("Swipe Shimmer/Band opacity", default: 1, in: 0...1) } // LOCAL-TUNER
    /// The label's opacity outside the band, which leaves the band room to read brighter.
    static var shimmerLabelOpacity: Double { Tuner.shared.value("Swipe Shimmer/Label opacity", default: 0.6, in: 0...1) } // LOCAL-TUNER
    /// Whether every label takes one period to sweep, so longer labels sweep faster, as GSConfirm does.
    static var shimmerScalesWithLabel: Bool { Tuner.shared.value("Swipe Shimmer/Scales with label", default: true) } // LOCAL-TUNER
    /// The time one sweep takes when it scales with the label.
    static var shimmerPeriod: TimeInterval { Tuner.shared.value("Swipe Shimmer/Period", default: 2.75, in: 0.5...8, unit: .seconds) } // LOCAL-TUNER
    /// The band's speed in points a second when it doesn't scale with the label.
    static var shimmerSpeed: Double { Tuner.shared.value("Swipe Shimmer/Speed", default: 71, in: 10...300) } // LOCAL-TUNER
    /// The band fading away when the sweep pauses, and back when it resumes.
    static var shimmerFade: TimeInterval { Tuner.shared.value("Swipe Shimmer/Fade", default: 0.2, in: 0...0.6, unit: .seconds) } // LOCAL-TUNER

    // MARK: - Failure

    static var shakeDistance: CGFloat { Tuner.shared.value("Swipe Failure/Shake distance", default: 8, in: 0...24, unit: .points) } // LOCAL-TUNER
    static var shakeCount: Int { Tuner.shared.value("Swipe Failure/Shake count", default: 3, in: 1...8) } // LOCAL-TUNER
    static var shakeDuration: TimeInterval { Tuner.shared.value("Swipe Failure/Shake duration", default: 0.4, in: 0.1...1, unit: .seconds) } // LOCAL-TUNER
    /// The `bannerError` wash the track takes while it shows the failure.
    static var failureTint: Double { Tuner.shared.value("Swipe Failure/Tint opacity", default: 0.35, in: 0...1) } // LOCAL-TUNER
    static var failureTintFade: TimeInterval { Tuner.shared.value("Swipe Failure/Tint fade", default: 0.15, in: 0...0.5, unit: .seconds) } // LOCAL-TUNER
    /// How long the failure shows before the control resets.
    static var failureHold: TimeInterval { Tuner.shared.value("Swipe Failure/Hold", default: 0.6, in: 0...2, unit: .seconds) } // LOCAL-TUNER

    // MARK: - Tuner

    private static func layout(_ name: String, _ value: CGFloat, _ range: ClosedRange<CGFloat>) -> CGFloat {
        Tuner.shared.value("Swipe Layout/\(name)", default: value, in: range, unit: .points) // LOCAL-TUNER
    }

    // Bakes back to `ChatSpring(duration:bounce:)` lets.
    private static func spring(_ key: String, _ duration: TimeInterval, _ bounce: Double) -> ChatSpring {
        let spring = Tuner.value(key, default: Spring(duration: duration, bounce: bounce), form: "ChatSpring(duration: {duration}, bounce: {bounce})") // LOCAL-TUNER
        return ChatSpring(duration: spring.duration, bounce: spring.bounce)
    }
}

extension ChatSpring {
    /// This spring as an animation, with its bounce removed when Reduce Motion is on.
    func animation(reduceMotion: Bool) -> Animation {
        reduceMotion ? .spring(duration: duration, bounce: 0) : animation
    }
}

/// The haptic styles the swipe control can tap with.
enum SwipeHapticStyle: String, CaseIterable, TunableEnum { // LOCAL-TUNER
    case impactSoft, impactSolid, impactRigid, impactLight, impactMedium, impactHeavy, selection, alignment, levelChange, start

    /// This style as feedback at `intensity`, which `selection`, `alignment`, `levelChange` and `start` ignore.
    func feedback(intensity: Double) -> SensoryFeedback {
        switch self {
        case .impactSoft: .impact(flexibility: .soft, intensity: intensity)
        case .impactSolid: .impact(flexibility: .solid, intensity: intensity)
        case .impactRigid: .impact(flexibility: .rigid, intensity: intensity)
        case .impactLight: .impact(weight: .light, intensity: intensity)
        case .impactMedium: .impact(weight: .medium, intensity: intensity)
        case .impactHeavy: .impact(weight: .heavy, intensity: intensity)
        case .selection: .selection
        case .alignment: .alignment
        case .levelChange: .levelChange
        case .start: .start
        }
    }
}

/// The glass the lens rim is drawn in.
enum SwipeLensGlass: String, CaseIterable, TunableEnum { // LOCAL-TUNER
    case clear, regular
}
