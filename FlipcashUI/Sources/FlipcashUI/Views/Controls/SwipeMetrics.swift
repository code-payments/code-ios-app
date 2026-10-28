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
    static var look: SwipeControlLook { Tuner.shared.value("Swipe/Look", default: SwipeControlLook.morphFill) } // LOCAL-TUNER

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

    /// The capsule's height, shared with the tray's capsule buttons.
    static var height: CGFloat { TrayMetrics.actionHeight }
    static var thumbInset: CGFloat { layout("Thumb inset", 4, 0...12) } // LOCAL-TUNER
    static var arrowSize: CGFloat { layout("Arrow size", 20, 12...32) } // LOCAL-TUNER
    /// The track's `action` wash, as today's control draws it.
    static var fillOpacity: Double { Tuner.shared.value("Swipe Layout/Fill opacity", default: 0.1, in: 0...0.3) } // LOCAL-TUNER
    /// The hairline's `textSecondary` opacity; 0.3 is `Metrics.inputFieldStrokeColor(highlighted: false)`.
    static var strokeOpacity: Double { Tuner.shared.value("Swipe Layout/Stroke opacity", default: 0.3, source: "Metrics.inputFieldStrokeColor(highlighted: false)", in: 0...1) } // LOCAL-TUNER
    static var disabledOpacity: Double { Tuner.shared.value("Swipe Layout/Disabled opacity", default: 0.4, in: 0...1) } // LOCAL-TUNER

    // MARK: - Label

    /// How far the label may shrink to fit one line at large Dynamic Type sizes.
    static var labelMinimumScale: CGFloat { Tuner.shared.value("Swipe Layout/Label min scale", default: 0.7, in: 0.5...1) } // LOCAL-TUNER
    /// Whether the label is wiped away from the left as the thumb passes.
    static var labelWipes: Bool { Tuner.shared.value("Swipe Layout/Label wipes", default: true) } // LOCAL-TUNER
    /// Where across the thumb the wipe's edge sits, from its leading edge (0) to its trailing edge (1).
    static var labelWipeEdge: CGFloat { Tuner.shared.value("Swipe Layout/Wipe edge", default: 1, in: 0...1) } // LOCAL-TUNER
    /// Whether what's left of the label fades as the thumb travels.
    static var labelFades: Bool { Tuner.shared.value("Swipe Layout/Label fades", default: true) } // LOCAL-TUNER

    // MARK: - Thumb

    /// The white tint over the thumb's glass.
    static var glassTint: Double { Tuner.shared.value("Swipe Layout/Glass tint", default: 0, in: 0...0.3) } // LOCAL-TUNER
    /// Whether the thumb's glass answers the finger the way system glass controls do.
    static var glassInteractive: Bool { Tuner.shared.value("Swipe Layout/Glass interactive", default: true) } // LOCAL-TUNER
    /// The hairline round the iOS 18 material thumb, as white opacity.
    static var fallbackHairline: Double { Tuner.shared.value("Swipe Layout/Fallback hairline", default: 0.2, in: 0...1) } // LOCAL-TUNER
    /// How far the idle nudge pushes the thumb right.
    static var nudgeDistance: CGFloat { layout("Nudge distance", 20, 0...40) } // LOCAL-TUNER

    // MARK: - Press

    /// The thumb's scale under the finger, for the glass thumb and the morph.
    static var pressScale: CGFloat { Tuner.shared.value("Swipe Motion/Press scale", default: 1.06, in: 1...1.3, unit: .multiplier) } // LOCAL-TUNER
    /// The thumb's opacity under the finger with Reduce Motion on, standing in for the scale.
    static var pressDim: Double { Tuner.shared.value("Swipe Motion/Press dim", default: 0.8, in: 0.3...1) } // LOCAL-TUNER
    /// The soft tap's strength at touch-down.
    static var touchHaptic: Double { Tuner.shared.value("Swipe Motion/Touch haptic", default: 0.5, in: 0...1) } // LOCAL-TUNER

    // MARK: - Motion

    /// The thumb settling: snapping back from a short drag, parking at the end, returning after a send.
    static var snapBack: ChatSpring { spring("Swipe Motion/Snap back", 0.5, 0) } // LOCAL-TUNER
    /// The thumb growing to fill the track on commit, in the morph look.
    static var morph: ChatSpring { spring("Swipe Motion/Morph", 0.4, 0) } // LOCAL-TUNER
    /// The thumb lifting under the finger and settling on release.
    static var press: ChatSpring { spring("Swipe Motion/Press", 0.3, 0.25) } // LOCAL-TUNER
    /// The idle nudge's push and return.
    static var nudge: ChatSpring { spring("Swipe Motion/Nudge", 0.25, 0) } // LOCAL-TUNER

    // MARK: - Lens

    /// The lens thumb's scale under the finger; GSConfirm's 1.15 stays inside a 54 pt track here.
    static var lensPressScale: CGFloat { Tuner.shared.value("Swipe Lens/Press scale", default: 1.12, in: 1...1.4, unit: .multiplier) } // LOCAL-TUNER
    static var lensRimWidth: CGFloat { Tuner.shared.value("Swipe Lens/Rim width", default: 2, in: 0.5...8, unit: .points) } // LOCAL-TUNER
    static var lensRimSoftness: CGFloat { Tuner.shared.value("Swipe Lens/Rim softness", default: 1.5, in: 0...6, unit: .points) } // LOCAL-TUNER
    static var lensRimTint: Double { Tuner.shared.value("Swipe Lens/Rim tint", default: 0.1, in: 0...0.5) } // LOCAL-TUNER
    /// How far the lens pulls the label at the rim.
    static var lensBend: CGFloat { Tuner.shared.value("Swipe Lens/Bend", default: 12, in: 0...30, unit: .points) } // LOCAL-TUNER
    /// How deep inside the rim the bend reaches, as a share of the lens's radius.
    static var lensBand: CGFloat { Tuner.shared.value("Swipe Lens/Band", default: 0.5, in: 0.05...1) } // LOCAL-TUNER
    /// The wipe's edge for the lens look, which shows the label through the thumb.
    static var lensWipeEdge: CGFloat { Tuner.shared.value("Swipe Lens/Wipe edge", default: 0.5, in: 0...1) } // LOCAL-TUNER

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
