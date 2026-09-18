//
//  TranscriptBlur.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit

/// The blur over a transcript the signed-in user is not allowed to read — a group chat whose
/// listener rules they do not satisfy.
///
/// Sits above the transcript and below the bar clip, so the gate panel naming the unmet requirement
/// stays sharp while everything it is talking about goes soft. The navigation bar is a sibling in
/// the navigation controller's view rather than a subview of this screen, so it stays sharp without
/// being excluded — the title, the picture and the member count all stay readable above a blurred
/// transcript, which is what the design shows.
///
/// The frosting itself is ``ChatBackdrop``'s, the same one a long press puts behind a lifted
/// message, including its dim: this blur stands alone with no context menu above it, so nothing
/// else is darkening the screen, and the material on its own lifts a near-black transcript's blacks
/// instead of hiding them.
@MainActor
final class TranscriptBlur {

    /// How long the blur takes to lift. Matches the bar's own swap between the gate panel and the
    /// composer, so the two land together.
    ///
    /// Only the lift is animated. Covering the transcript happens in one frame: fading the blur in
    /// animates readable messages into covered ones, which puts the thing being withheld on screen
    /// for the length of the fade. Revealing has no such problem — by then the viewer is allowed to
    /// see what is underneath, so the transition is free.
    private static let revealDuration: TimeInterval = 0.25

    private let effectView = UIVisualEffectView(effect: nil)
    /// Layered in the effect view's content view, so it fades with the blur and needs no separate
    /// animation of its own.
    private let dim = UIView()
    /// Holds the material at ``ChatBackdrop/blurFraction``. Kept for the life of the screen, and
    /// stopped below before it deallocates — see ``ChatBackdrop/frost(_:)``.
    private var strength: UIViewPropertyAnimator?

    /// The blur itself, so anything meant to be seen *through* it can be layered directly beneath.
    var view: UIView { effectView }

    /// Whether the transcript is covered. Snaps on and fades off — see ``revealDuration``. Setting
    /// it to the value it already has is a no-op, so a re-render reporting the same gate doesn't
    /// restart the fade.
    var isShown = false {
        didSet {
            guard isShown != oldValue else { return }
            guard !isShown else {
                effectView.alpha = 1
                return
            }
            UIView.animate(withDuration: Self.revealDuration) {
                self.effectView.alpha = 0
            }
        }
    }

    /// Adds the blur to `host`, pinned to its edges and layered directly under `sibling`. Called
    /// once, from `viewDidLoad`.
    ///
    /// Takes its opacity from ``isShown`` rather than starting hidden: the gate is assigned to the
    /// controller before its view loads, so a chat that opens already gated has set this to true by
    /// the time we get here, and zeroing the alpha would uncover the transcript until something
    /// else changed the gate.
    func install(in host: UIView, below sibling: UIView) {
        effectView.translatesAutoresizingMaskIntoConstraints = false
        effectView.alpha = isShown ? 1 : 0
        // Takes the touches that would otherwise reach the transcript: a blurred view that still
        // scrolls reads as broken, and every fetch behind it is one the server would deny anyway.
        effectView.isUserInteractionEnabled = true

        dim.translatesAutoresizingMaskIntoConstraints = false
        dim.backgroundColor = .black
        dim.alpha = ChatBackdrop.dimAlpha
        dim.isUserInteractionEnabled = false
        effectView.contentView.addSubview(dim)

        host.insertSubview(effectView, belowSubview: sibling)
        NSLayoutConstraint.activate([
            effectView.topAnchor.constraint(equalTo: host.topAnchor),
            effectView.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            effectView.bottomAnchor.constraint(equalTo: host.bottomAnchor),

            dim.topAnchor.constraint(equalTo: effectView.contentView.topAnchor),
            dim.leadingAnchor.constraint(equalTo: effectView.contentView.leadingAnchor),
            dim.trailingAnchor.constraint(equalTo: effectView.contentView.trailingAnchor),
            dim.bottomAnchor.constraint(equalTo: effectView.contentView.bottomAnchor),
        ])

        strength = ChatBackdrop.frost(effectView)
    }

    isolated deinit {
        strength?.stopAnimation(true)
    }
}
#endif
