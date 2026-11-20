//
//  ChatBackdrop.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit

/// The frosting the chat screen puts over its own transcript — behind a lifted message's menu,
/// behind the edit that can follow it, and over a transcript the viewer is not allowed to read.
///
/// One definition because it is one effect on screen: the gate blurs the same bubbles the long
/// press does, for a different reason, and anyone who meets both in a session sees any drift
/// between them. They share the material and the dim and differ only in strength, because the
/// gate's job is to withhold. A recipe rather than a view, because the callers own their layers
/// differently — ``MessageBackdrop`` moves its blur between hosts mid-interaction,
/// ``TranscriptBlur`` pins one to a screen for its lifetime.
@MainActor
enum ChatBackdrop {

    /// How much of the material's blur is used behind a lifted message, its edit, and the
    /// payment-request deck: lighter than the gate's.
    ///
    /// A `UIBlurEffect` has no radius to set — every style is the same radius under a different
    /// tint — so the effect is applied through an animator that is paused part-way, which is the
    /// only handle on its strength. At full strength the transcript smears into flat colour.
    static let blurFraction: CGFloat = 0.1

    /// How much of the material's blur is used over a transcript the viewer is not allowed to read.
    /// Kept apart from ``blurFraction`` so a lighter decorative frost never makes withheld messages
    /// legible; Android frosts the same screen at a 25dp radius, and this is matched to that.
    static let gateBlurFraction: CGFloat = 0.25

    /// The black that goes with the blur everywhere it is used, under a context menu's own dimming
    /// too.
    ///
    /// The material is a translucent *light* veil, so over a near-black transcript it raises the
    /// black level — blur on its own hands back something paler than the sharp transcript beside it.
    /// A long press raises this with the blur on its first frame, under the menu as well, and an
    /// edit keeps it once the menu has gone.
    static let dimAlpha: CGFloat = 0.33

    /// Applies the material to `view` at `fraction` of its strength, ``blurFraction`` unless the
    /// caller says otherwise, and hands back the animator holding it there.
    ///
    /// The animator is a dial, not an animation: it is never played out, but it has to be kept alive
    /// for the effect to stay applied, and stopped by hand before it deallocates — a property
    /// animator still active when it goes traps. Teardown belongs to the caller, which is the only
    /// side that knows when its blur is finished with.
    static func frost(_ view: UIVisualEffectView, fraction: CGFloat = blurFraction) -> UIViewPropertyAnimator {
        let material = UIBlurEffect(style: .systemUltraThinMaterialDark)
        let strength = UIViewPropertyAnimator(duration: 1, curve: .linear) { view.effect = material }
        strength.fractionComplete = fraction
        return strength
    }
}
#endif
