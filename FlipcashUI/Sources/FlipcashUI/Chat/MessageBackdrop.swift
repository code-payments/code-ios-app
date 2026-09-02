//
//  MessageBackdrop.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit

/// The blur that sits behind a lifted message — the context menu's platter, and the edit that can
/// follow it.
///
/// UIKit only dims the content behind a context menu, leaving every bubble legible under the
/// platter. WhatsApp — the reference for this interaction — blurs it, so the lifted bubble is the
/// one sharp thing on screen. The blur covers whichever view it is presented over, and UIKit puts
/// the menu itself in a container above the window's root, so the platter and the lift stay sharp.
///
/// Choosing Edit holds the same blur past the menu rather than fading it and raising a second one,
/// which is what keeps the transcript from flashing back to legible between the two states. Held,
/// the blur moves below the composer bar so the field stays sharp and usable, carries a detached
/// copy of the edited bubble above itself, and takes the taps that land outside it.
@MainActor
final class MessageBackdrop {

    /// Matches the fade UIKit uses for its own dimming when no animator is supplied.
    private static let fallbackDuration: TimeInterval = 0.2

    /// Called when the held blur is tapped — the way out of an edit, as tapping outside the message
    /// is in WhatsApp. Never fires while a context menu owns the screen: the menu's own container
    /// sits above the blur and takes those taps.
    var onTap: (() -> Void)?

    /// Whether the blur is being kept past the menu that raised it.
    private(set) var isHeld = false

    private let effect = UIBlurEffect(style: .systemUltraThinMaterialDark)
    private var effectView: UIVisualEffectView?
    private var spotlight: UIView?

    /// Fades the blur in over `host`, riding `animator` so it lands with the menu. Presenting twice
    /// is a no-op: the display callback fires once for the lift and again for the menu.
    func present(over host: UIView, animator: UIContextMenuInteractionAnimating?) {
        guard effectView == nil else { return }

        let blur = UIVisualEffectView(effect: nil)
        // Purely decorative until it is held — the menu's own container sits above this and owns
        // every touch.
        blur.isUserInteractionEnabled = false
        blur.frame = host.bounds
        blur.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.addSubview(blur)
        effectView = blur

        let fadeIn = { blur.effect = self.effect }
        if let animator {
            animator.addAnimations(fadeIn)
        } else {
            UIView.animate(withDuration: Self.fallbackDuration, animations: fadeIn)
        }
    }

    /// Keeps the blur up after the menu that raised it goes, moving it under `bar` so the composer
    /// stays sharp, and starts taking taps. The message itself is floated separately, by
    /// `setSpotlight`, once the menu has finished putting its lifted preview back.
    func hold(under bar: UIView) {
        guard let blur = effectView, let host = bar.superview else { return }
        isHeld = true

        blur.frame = host.bounds
        host.insertSubview(blur, belowSubview: bar)

        blur.isUserInteractionEnabled = true
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        blur.addGestureRecognizer(tap)
    }

    /// Floats `bubble` — a detached copy of the edited message — above a held blur, at `frame` in
    /// the blur's own coordinates.
    ///
    /// A copy rather than a hole cut in the blur: a `UIVisualEffectView` renders its backdrop
    /// through a private layer that ignores `layer.mask`, and the real bubble can't be raised out of
    /// the collection view that owns it.
    func setSpotlight(_ bubble: UIView, at frame: CGRect) {
        guard let blur = effectView, isHeld, let host = blur.superview else { return }
        spotlight?.removeFromSuperview()
        bubble.frame = frame
        bubble.isUserInteractionEnabled = false
        host.insertSubview(bubble, aboveSubview: blur)
        spotlight = bubble
    }

    /// Whether a copy is currently floating.
    var hasSpotlight: Bool { spotlight != nil }

    /// Moves the floated copy as the keyboard and the bar reflow the transcript underneath it. A
    /// no-op when nothing is floating, so a layout pass before the copy exists is harmless.
    func moveSpotlight(to frame: CGRect) {
        spotlight?.frame = frame
    }

    /// Fades the blur out with the menu and takes it off screen once it has gone. A held blur
    /// ignores this: the edit it belongs to outlives the menu, and ends it with `release`.
    func dismiss(animator: UIContextMenuInteractionAnimating?) {
        guard !isHeld, let blur = effectView else { return }
        effectView = nil

        let fadeOut = { blur.effect = nil }
        if let animator {
            animator.addAnimations(fadeOut)
            animator.addCompletion { blur.removeFromSuperview() }
        } else {
            UIView.animate(withDuration: Self.fallbackDuration, animations: fadeOut) { _ in
                blur.removeFromSuperview()
            }
        }
    }

    /// Fades a held blur out, once whatever was holding it is over.
    func release() {
        guard isHeld, let blur = effectView else { return }
        isHeld = false
        effectView = nil

        let bubble = spotlight
        spotlight = nil
        UIView.animate(withDuration: Self.fallbackDuration) {
            blur.effect = nil
            bubble?.alpha = 0
        } completion: { _ in
            blur.removeFromSuperview()
            bubble?.removeFromSuperview()
        }
    }

    @objc private func handleTap() {
        onTap?()
    }
}
#endif
