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
/// between them. A recipe rather than a view, because the callers own their layers differently —
/// ``MessageBackdrop`` moves its blur between hosts mid-interaction, ``TranscriptBlur`` pins one to
/// a screen for its lifetime.
@MainActor
enum ChatBackdrop {

    /// How much of the material's blur is used. A `UIBlurEffect` has no radius to set — every style
    /// is the same radius under a different tint — so the effect is applied through an animator that
    /// is paused part-way, which is the only handle on its strength. At full strength the transcript
    /// smears into flat colour; Android frosts the same screen at a 25dp radius and reads far softer,
    /// and this is matched to that.
    static let blurFraction: CGFloat = 0.4

    /// The black that goes with the blur wherever nothing else is darkening the screen.
    ///
    /// The material is a translucent *light* veil, so over a near-black transcript it raises the
    /// black level — blur on its own hands back something paler than the sharp transcript beside it.
    /// Under a context menu UIKit's own dimming covers that: measured on the same patch of empty
    /// transcript, rgb 23 under the menu against 44 after it. Everywhere else this stands in for it,
    /// set well below the value that matches the menu exactly — matching it left an edit as dark as
    /// the menu, which is heavier than Android's frosting of the same screen, and the menu's own
    /// dimming isn't ours to lighten to meet it.
    static let dimAlpha: CGFloat = 0.2

    /// Applies the material to `view` at ``blurFraction``, and hands back the animator holding it
    /// there.
    ///
    /// The animator is a dial, not an animation: it is never played out, but it has to be kept alive
    /// for the effect to stay applied, and stopped by hand before it deallocates — a property
    /// animator still active when it goes traps. Teardown belongs to the caller, which is the only
    /// side that knows when its blur is finished with.
    static func frost(_ view: UIVisualEffectView) -> UIViewPropertyAnimator {
        let material = UIBlurEffect(style: .systemUltraThinMaterialDark)
        let strength = UIViewPropertyAnimator(duration: 1, curve: .linear) { view.effect = material }
        strength.fractionComplete = blurFraction
        return strength
    }
}
#endif
