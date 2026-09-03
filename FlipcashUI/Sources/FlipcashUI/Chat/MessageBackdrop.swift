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
/// it stays over the same host, so an edit is as soft as the menu was rather than sparing the
/// navigation bar; it slides under that bar, so the back button stays legible above it; it stops at
/// the top of the composer, the one piece of chrome an edit needs sharp; and it carries a detached
/// copy of the edited bubble above itself and takes the taps that land outside it.
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
    /// Holds the floated copy and clips it to the blur, so a copy of a row that has scrolled past
    /// either edge can't draw over the composer or the navigation bar.
    private var spotlightClip: UIView?
    /// The composer bar a held blur stops short of, re-measured on every layout pass.
    private weak var clearance: UIView?

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

    /// Keeps the blur up after the menu that raised it goes, and starts taking taps. It stays over
    /// the host the menu blurred, so nothing sharpens on the way into an edit, and only its z-order
    /// and its bottom edge change: under `navigationBar`, so the back button stays legible and
    /// tappable, and stopping at the top of `bar`, so the composer does too. The message itself is
    /// floated separately, by `setSpotlight`, once the menu has finished putting its lifted preview
    /// back.
    func hold(clearing bar: UIView, under navigationBar: UIView?) {
        guard let blur = effectView, let host = blur.superview else { return }
        isHeld = true
        clearance = bar

        if let navigationBar, navigationBar.superview === host {
            host.insertSubview(blur, belowSubview: navigationBar)
        }
        // The frame is driven by the bar from here on, so the host can no longer resize it.
        blur.autoresizingMask = []

        let clip = UIView()
        clip.clipsToBounds = true
        clip.isUserInteractionEnabled = false
        host.insertSubview(clip, aboveSubview: blur)
        spotlightClip = clip

        layoutHeld()

        blur.isUserInteractionEnabled = true
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        blur.addGestureRecognizer(tap)
    }

    /// Re-measures a held blur against the composer bar, which rises and falls with the keyboard.
    /// A no-op when nothing is held, so a layout pass outside an edit is harmless.
    func layoutHeld() {
        guard isHeld, let blur = effectView, let host = blur.superview, let bar = clearance else { return }
        let barTop = bar.convert(bar.bounds, to: host).minY
        blur.frame = CGRect(x: 0, y: 0, width: host.bounds.width, height: max(barTop, 0))
        spotlightClip?.frame = blur.frame
    }

    /// Floats `bubble` — a detached copy of the edited message — above a held blur, at `frame` in
    /// the blur's own coordinates.
    ///
    /// A copy rather than a hole cut in the blur: a `UIVisualEffectView` renders its backdrop
    /// through a private layer that ignores `layer.mask`, and the real bubble can't be raised out of
    /// the collection view that owns it. It goes in the clip rather than straight into the host, so
    /// it stops where the blur does instead of covering the composer.
    func setSpotlight(_ bubble: UIView, at frame: CGRect) {
        guard isHeld, let clip = spotlightClip else { return }
        spotlight?.removeFromSuperview()
        bubble.frame = frame
        bubble.isUserInteractionEnabled = false
        clip.addSubview(bubble)
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
        clearance = nil

        let bubble = spotlight
        spotlight = nil
        let clip = spotlightClip
        spotlightClip = nil
        UIView.animate(withDuration: Self.fallbackDuration) {
            blur.effect = nil
            bubble?.alpha = 0
        } completion: { _ in
            blur.removeFromSuperview()
            clip?.removeFromSuperview()
        }
    }

    @objc private func handleTap() {
        onTap?()
    }
}
#endif
