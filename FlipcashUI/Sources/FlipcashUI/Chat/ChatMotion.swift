//
//  ChatMotion.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit
import SwiftUI
import ChatLayout
import FlipcashCore

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
        options: UIView.AnimationOptions = [],
        _ animations: @escaping () -> Void,
        completion: ((Bool) -> Void)? = nil
    ) {
        UIView.animate(
            springDuration: duration,
            bounce: bounce,
            initialSpringVelocity: initialVelocity,
            delay: delay,
            options: options,
            animations: animations,
            completion: completion
        )
    }

    /// The Core Animation form, for properties `UIView` animations can't drive — a `CAShapeLayer`'s
    /// `path`, in this codebase.
    public func layerAnimation(keyPath: String, from: Any? = nil, to: Any? = nil) -> CASpringAnimation {
        let animation = CASpringAnimation(keyPath: keyPath)
        animation.mass = Self.mass
        animation.stiffness = stiffness
        animation.damping = damping
        animation.initialVelocity = 0
        animation.fromValue = from
        animation.toValue = to
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
    public static let insertion = ChatSpring(duration: 0.27, bounce: 0.15)
    /// The list settling at the bottom after content is appended.
    public static let scroll = ChatSpring(duration: 0.30, bounce: 0.12)
    /// The transcript following the bottom chrome — the keyboard, or the bar resizing around a
    /// multiline draft.
    ///
    /// The keyboard case inherits the system curve directly (see
    /// `ChatViewController.scrollViewDidChangeAdjustedContentInset`) rather than this spring, which
    /// is the same intent the zero bounce encodes: any overshoot would fight the keyboard. The bar
    /// case wants the same stillness, since a send runs it alongside `insertion` and `scroll`.
    public static let keyboardScroll = ChatSpring(duration: 0.30, bounce: 0)
    /// The bar growing and shrinking around the reply strip.
    ///
    /// The one spring in this file taken from a reference rather than the prototype: WhatsApp's
    /// reply surface, measured frame by frame off a 60fps capture — 13 frames out, 14 back,
    /// monotonic, no overshoot in either direction. Bounce is zero for the same reason
    /// `keyboardScroll`'s is: the transcript's bottom inset tracks this height every frame, and a bar
    /// that overshoots drags the messages past their resting place and back.
    ///
    /// Lengthened from the reference's 0.22s to 0.28s: the mention list resizing around the strip
    /// rides this spring too, and at 0.22s that change of shape read as abrupt.
    public static let replySurface = ChatSpring(duration: 0.28, bounce: 0)
    /// The reply strip merging back into the open mention list. Slower than `replySurface`: a glass
    /// shape leaving its container settles faster than one arriving, so this matches the peel.
    public static let replyMerge = ChatSpring(duration: 0.5, bounce: 0)
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
    /// A bubble's corners flattening as a bubble run forms. Deliberately the slowest of the
    /// set, so the regrouping reads as settling rather than as a second event.
    public static let corner = ChatSpring(duration: 0.45, bounce: 0.32)
    /// Rows resizing in place (a receipt moving, a reaction, a status or an edit changing a row's
    /// height), which glides the transcript to its new layout and never bounces it.
    public static let reflow = ChatSpring(duration: 0.35, bounce: 0)
    /// The typing bubble growing into the incoming message that replaces it. The whole update rides
    /// it, so the rows above make room on the same curve the bubble grows on and its top edge never
    /// runs into the row above.
    public static let fromTyping = ChatSpring(duration: 0.20, bounce: 0.21)
    /// A reaction pill arriving under its bubble. A touch more bounce than a bubble's arrival, since
    /// the pill is small and the tap that made it wants an answer.
    public static let reaction = ChatSpring(duration: 0.32, bounce: 0.35)
    /// A reaction pill leaving. Quicker than its arrival and without bounce: a removal is an
    /// acknowledgement, not an event, and an overshoot would read as the pill coming back.
    public static let reactionExit = ChatSpring(duration: 0.2, bounce: 0)
    /// Pills sliding to make room, or closing a gap. The transcript resizes a row in place on
    /// `reflow`, so the pills travel on the same spring as the space they move into.
    public static let reactionReflow = reflow
    /// A pill's count or selected state changing in place.
    public static let reactionChange = ChatSpring(duration: 0.24, bounce: 0)
    /// The attach panel growing out of `+` and collapsing back. The bar's own spring, since it moves
    /// a piece of the bar; no reference frames were measured for it. A morph that also opens or
    /// closes the camera or photo card rides `attachCard` instead.
    public static let attachPanel = swap
    /// The camera or photo card growing out of the panel, and closing into a chip or back into the
    /// panel. Zero bounce, from `keyboardScroll`: an overshoot on a card half the screen tall carries
    /// its edge well past where it rests.
    public static let attachCard = keyboardScroll
    /// The leaving side's content fading out while the panel and a card morph into each other: done in
    /// the first third of `attachCard`, so only the shared surface is seen changing shape.
    public static let attachContentOut = Animation.easeOut(duration: attachCard.duration * 0.35)
    /// The arriving side's content fading in once the shared surface has nearly landed, so the two
    /// directions of the morph are one motion played either way. Eased out: an ease-in ends at full
    /// speed, and the content popped the last of the way in.
    public static let attachContentIn = Animation.easeOut(duration: attachCard.duration * 0.55)
        .delay(attachCard.duration * 0.45)
    /// A chip arriving in or leaving the composer's strip, and its neighbours sliding to make room.
    /// Small and tapped-for like a reaction pill, so it travels on the pill's spring.
    public static let composerChip = reaction

    // MARK: - Scales

    /// A bubble's starting scale as it is inserted, grown from its bottom corner on the sender's side.
    public static let insertionScale: CGFloat = 0.90
    /// "Delivered"'s starting scale as it appears.
    public static let deliveredScale: CGFloat = 0.95
    /// "Delivered"'s ending scale as it gives way to "Read".
    public static let deliveredExitScale: CGFloat = 0.90
    /// "Read"'s starting scale as it replaces "Delivered".
    public static let readEnterScale: CGFloat = 0.90
    /// The bottom bar's starting scale as it swaps states.
    public static let swapScale: CGFloat = 0.95
    /// A reaction pill's starting scale as it springs in.
    public static let reactionEnterScale: CGFloat = 0.4
    /// A reaction pill's ending scale as it leaves. Shrinks less than it grew, so the exit is felt
    /// as the pill stepping back rather than collapsing.
    public static let reactionExitScale: CGFloat = 0.6
    /// How far below its slot a row appended at the bottom starts, as a share of the room its arrival
    /// makes. At 1 it rides up in step with the rows it pushes, so it never overlaps the one above.
    public static let insertionRise: CGFloat = 0.35
    /// The attach panel's starting scale as it grows out of `+`, and its ending scale as it
    /// collapses back. The pill's figure: small enough that the panel reads as coming out of the
    /// button rather than fading in beside it.
    public static let attachPanelEnterScale: CGFloat = reactionEnterScale
    /// A composer chip's starting scale as it arrives, and its ending scale as it is removed.
    public static let composerChipEnterScale: CGFloat = reactionEnterScale

    // MARK: - Timing

    /// How long a dismissed context menu's bubble takes to settle back into its row. Work held for
    /// the menu runs after this rather than on UIKit's completion, which trails the landing.
    public static let contextMenuLanding: TimeInterval = 0.3

    /// The attention flash a jumped-to message plays when a reply quote is tapped, in three parts:
    /// it lights quickly, holds long enough to be found by eye after the scroll settles, then fades
    /// slowly so the transcript is left as it was rather than switched back.
    public static let attentionRise: TimeInterval = 0.15
    public static let attentionHold: TimeInterval = 0.45
    public static let attentionFade: TimeInterval = 0.40
    /// The whole flash, end to end.
    public static var attentionDuration: TimeInterval { attentionRise + attentionHold + attentionFade }

    /// How long a sent message holds before its "Delivered" line appears. A floor, not a fixed
    /// delay: the line waits for server confirmation too, whichever is later.
    public static let deliveredDelay: TimeInterval = 0.70
    /// How long a line a row has just given up takes to fade out as the next row's line reveals.
    ///
    /// Bound by the geometry, not by taste: the row below glides up into the line's place on
    /// `reflow` and draws over it, so the line must be gone before that row's top edge arrives. In a
    /// bubble run that edge sits one tight row gap under the line and gets there about 40 % into the
    /// glide, 0.08 s on the 0.35 s reflow; a longer fade is cut off by the arriving bubble.
    public static let receiptExitFade: TimeInterval = 0.08

    /// How long a message growing out of the typing bubble keeps its text hidden, so the words
    /// arrive into a bubble that has mostly taken its shape rather than spilling out of the dots'.
    public static let fromTypingTextDelay: TimeInterval = 0.058
    /// How long that text takes to fade in once it starts.
    public static let fromTypingTextFade: TimeInterval = 0.155
    /// How long the dots take to fade out where they stood as their bubble grows away from them.
    public static let fromTypingDotsFade: TimeInterval = 0.08

    // MARK: - Insertion geometry

    /// Where an inserted row starts before it springs into place: transparent and scaled down by
    /// `insertionScale` about its bottom corner on the sender's side, so the bubble grows out of its
    /// side of the thread rather than out of thin air. A row with no sender (a date separator, the
    /// profile card) scales about its centre.
    ///
    /// The off-centre anchor rides in the transform rather than in `center`, because ChatLayout
    /// overwrites the pending animation's `frame` — and with it `center` — when a self-sizing insert
    /// re-measures mid-flight. `transform` is what survives that, so the anchor has to live there.
    /// Assignment is absolute, so re-applying on a re-measure is safe.
    ///
    /// `rise` starts the row that many points below its slot. A row appended at the bottom passes
    /// the room its arrival makes: the rows above are carried up by exactly that much on the same
    /// spring, so the two travel together and the arrival reads as pushing the thread up rather than
    /// appearing on top of the row above while that row is still getting out of the way.
    ///
    /// Takes the attributes rather than reaching for a collection view, so the geometry is testable
    /// without a layout pass.
    @MainActor public static func applyInsertionState(to attributes: ChatLayoutAttributes, sender: ChatMessage.Sender?, rise: CGFloat = 0) {
        attributes.alpha = 0
        let scale = CGAffineTransform(scaleX: insertionScale, y: insertionScale)
        let lift = CGAffineTransform(translationX: 0, y: rise)
        guard let sender else {
            attributes.transform = scale.concatenating(lift)
            return
        }
        // A row is full-width, so scaling about its centre pulls both edges in by half the lost
        // width. Translating back out by that much holds the sender's edge still — and holds it at
        // every point of the spring, overshoot included, because both parts interpolate together.
        // The same goes for the bottom edge, so the bubble grows out of its bottom corner on the
        // sender's side: the corner nearest the composer it came from.
        let anchor = (1 - insertionScale) * attributes.frame.width / 2
        let bottom = (1 - insertionScale) * attributes.frame.height / 2
        attributes.transform = scale.concatenating(
            CGAffineTransform(translationX: sender == .me ? anchor : -anchor, y: bottom + rise)
        )
    }
}
#endif
