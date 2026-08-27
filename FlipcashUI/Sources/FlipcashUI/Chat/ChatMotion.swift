//
//  ChatMotion.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit
import SwiftUI

/// A spring expressed the way the design tuned it: perceptual `duration` and `bounce`, the same two
/// numbers SwiftUI's `.spring(duration:bounce:)` takes.
///
/// The conversation animates across three systems — SwiftUI in the bottom bar, `UIView` animations
/// in the transcript, and `CAAnimation` for layer paths that `UIView` can't drive. All three accept
/// this parameterization on iOS 17+, so one value type vends all three forms and the tuned numbers
/// stay in one place.
public nonisolated struct ChatSpring: Hashable, Sendable {

    /// Perceptual duration: roughly how long the motion reads as taking, not its settling time.
    public let duration: TimeInterval
    /// 0 is critically damped; positive values overshoot.
    public let bounce: Double

    public init(duration: TimeInterval, bounce: Double) {
        self.duration = duration
        self.bounce = bounce
    }

    // MARK: - Physics

    // The mass Core Animation is given below. Fixing it at 1 makes `stiffness` and `damping`
    // absolute rather than relative, which is what the derivations assume.
    private static let mass: Double = 1

    /// Damping ratio, where 1 is critically damped.
    public var dampingRatio: Double { 1 - bounce }

    /// Spring constant for a unit mass.
    public var stiffness: Double {
        let omega = 2 * Double.pi / duration
        return omega * omega
    }

    /// Viscous damping coefficient for a unit mass.
    public var damping: Double {
        4 * Double.pi * dampingRatio / duration
    }

    // MARK: - Forms

    /// The SwiftUI form, for the bottom bar.
    public var animation: Animation {
        .spring(duration: duration, bounce: bounce)
    }

    /// Runs `animations` on this spring. The UIKit form takes the same two numbers as the SwiftUI
    /// one, so nothing is converted or approximated between them.
    @MainActor public func animate(
        delay: TimeInterval = 0,
        initialVelocity: CGFloat = 0,
        _ animations: @escaping () -> Void,
        completion: ((Bool) -> Void)? = nil
    ) {
        UIView.animate(
            springDuration: duration,
            bounce: bounce,
            initialSpringVelocity: initialVelocity,
            delay: delay,
            animations: animations,
            completion: completion
        )
    }

    /// The Core Animation form, for properties `UIView` animations can't drive — a `CAShapeLayer`'s
    /// `path`, in this codebase. The caller supplies `fromValue`/`toValue`.
    public func layerAnimation(keyPath: String) -> CASpringAnimation {
        let animation = CASpringAnimation(keyPath: keyPath)
        animation.mass = Self.mass
        animation.stiffness = stiffness
        animation.damping = damping
        animation.initialVelocity = 0
        // Not `duration`: that is the perceptual figure, and cutting a `CAAnimation` off there
        // snaps the remaining travel. `settlingDuration` is how long the spring actually needs.
        animation.duration = animation.settlingDuration
        return animation
    }
}

/// Every animation the conversation transcript runs, in one place.
///
/// The values come from the tuned prototype's motion spec; treat this as the source of truth and
/// change a spring here rather than at a call site.
public nonisolated enum ChatMotion {

    // MARK: - Springs

    /// A bubble arriving in the transcript. The quickest of the set — the message should feel
    /// already-there rather than flown-in.
    public static let insertion = ChatSpring(duration: 0.23, bounce: 0.27)
    /// The list settling at the bottom after content is appended.
    public static let scroll = ChatSpring(duration: 0.30, bounce: 0.12)
    /// The scroll that accompanies the keyboard.
    ///
    /// Nothing calls this today. The transcript inherits the system keyboard curve directly (see
    /// `ChatViewController.scrollViewDidChangeAdjustedContentInset`), which is the same intent this
    /// spring's zero bounce encodes — any overshoot would fight the keyboard. It stays defined so
    /// the vocabulary is complete and the spec's eight springs are all covered by the physics test.
    public static let keyboardScroll = ChatSpring(duration: 0.30, bounce: 0)
    /// The "Delivered" line appearing under a sent bubble. Slow and gentle: it arrives after the
    /// message has landed and shouldn't compete with it.
    public static let delivered = ChatSpring(duration: 0.40, bounce: 0.12)
    /// "Delivered" swapping to "Read" in place. Snappier and bouncier than the reveal — this one is
    /// a reaction to the other person, so it should feel live.
    public static let read = ChatSpring(duration: 0.26, bounce: 0.26)
    /// The bottom bar swapping between its action and composer states.
    public static let swap = ChatSpring(duration: 0.27, bounce: 0.31)
    /// The send arrow scaling in and out of the composer.
    public static let sendButton = ChatSpring(duration: 0.17, bounce: 0.34)
    /// A bubble's corners flattening as a same-sender run forms. Deliberately the slowest of the
    /// set, so the regrouping reads as settling rather than as a second event.
    public static let corner = ChatSpring(duration: 0.45, bounce: 0.32)

    // MARK: - Scales

    /// A bubble's starting scale as it is inserted, grown from its own aligned edge.
    public static let insertionScale: CGFloat = 0.95
    /// "Delivered"'s starting scale as it appears.
    public static let deliveredScale: CGFloat = 0.95
    /// "Delivered"'s ending scale as it gives way to "Read".
    public static let deliveredExitScale: CGFloat = 0.90
    /// "Read"'s starting scale as it replaces "Delivered".
    public static let readEnterScale: CGFloat = 0.90
    /// The bottom bar's starting scale as it swaps states.
    public static let swapScale: CGFloat = 0.95

    // MARK: - Timing

    /// How long a sent message holds before its "Delivered" line appears. A floor, not a fixed
    /// delay: the line waits for server confirmation too, whichever is later.
    public static let deliveredDelay: TimeInterval = 0.70
}
#endif
