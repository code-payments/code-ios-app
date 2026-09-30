//
//  MessageBackdrop.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit

/// The blur that sits behind a lifted message — its reaction strip and menu, and the edit that can
/// follow them.
///
/// WhatsApp — the reference for this interaction — blurs the transcript behind a long-pressed
/// message, so the lifted bubble is the one sharp thing on screen. The blur covers whichever view it
/// is presented over, and the lift itself sits in a window above it (`MessageLiftOverlay`), so the
/// bubble, strip and menu stay sharp.
///
/// Choosing Edit holds the same blur past the menu rather than fading it and raising a second one,
/// which is what keeps the transcript from flashing back to legible between the two states. Held, it
/// slides down the hierarchy to just under the composer, so the transcript stays soft to the bottom
/// of the screen while the composer and the navigation bar — the two pieces of chrome an edit needs
/// sharp — draw over it; and it carries a detached copy of the edited bubble above itself and takes
/// the taps that land outside it.
@MainActor
final class MessageBackdrop {

    /// How long the blur takes to fade in or out.
    private static let fadeDuration: TimeInterval = 0.2

    /// Called when the held blur is tapped — the way out of an edit, as tapping outside the message
    /// is in WhatsApp. Never fires while a lift owns the screen: the lift's window sits above the
    /// blur and takes those taps.
    var onTap: (() -> Void)?

    /// Whether the blur is being kept past the menu that raised it.
    private(set) var isHeld = false

    private var effectView: UIVisualEffectView?
    /// Holds the blur at ``ChatBackdrop/blurFraction``, and is stopped by hand in `dismiss` and
    /// `release` — see ``ChatBackdrop/frost(_:)``.
    private var blurStrength: UIViewPropertyAnimator?
    private var spotlight: UIView?
    /// Replaces the menu's dimming once the menu is gone. Lives inside the blur, so it is clipped
    /// and framed with it and sits under the floated copy.
    private var dim: UIView?
    /// Holds the floated copy and clips it to the composer bar, so a copy of a row that has scrolled
    /// past either edge can't draw over the composer or the navigation bar.
    private var spotlightClip: UIView?
    /// The composer bar the floated copy stops short of, re-measured on every layout pass.
    private weak var clearance: UIView?

    /// Fades the blur in over `host`. Presenting twice is a no-op.
    func present(over host: UIView) {
        guard effectView == nil else { return }

        let blur = UIVisualEffectView(effect: nil)
        // Purely decorative until it is held — the lift's window sits above this and owns every touch.
        blur.isUserInteractionEnabled = false
        blur.frame = host.bounds
        blur.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        blur.alpha = 0
        host.addSubview(blur)
        effectView = blur

        // The fade is the view's own alpha, which is also what a partly-applied effect leaves
        // available to animate.
        blurStrength = ChatBackdrop.frost(blur)

        UIView.animate(withDuration: Self.fadeDuration) { blur.alpha = 1 }
    }

    /// Keeps the blur up after the menu that raised it goes, and starts taking taps. Nothing
    /// sharpens on the way into an edit: only the blur's z-order changes, dropping just below `bar`
    /// in the bar's own superview. That leaves it above the transcript, so the transcript stays
    /// soft; below the composer, so the composer's own chrome stays sharp; and below the navigation
    /// bar, since the screen it moves into already sits under it — the back button stays legible and
    /// tappable. Sitting behind the composer rather than stopping at its top edge is what lets it run
    /// to the bottom of the screen: the bar's background is a gradient that clears at its own top and
    /// its controls are glass, so a blur that stopped short would show a band of sharp transcript
    /// through them. The message itself is floated separately, by `setSpotlight`, once the menu has
    /// finished putting its lifted preview back.
    func hold(clearing bar: UIView, under navigationBar: UIView?) {
        guard let blur = effectView, let host = blur.superview, let barHost = bar.superview else { return }
        isHeld = true
        clearance = bar

        barHost.insertSubview(blur, belowSubview: bar)
        // The frame is driven by the layout pass from here on, so the host can no longer resize it.
        blur.autoresizingMask = []

        // Fade the stand-in dim in now, while the menu is still up: its own dimming fades out with
        // the dismissal, so the two cross and the screen never brightens between the states.
        let dim = UIView(frame: blur.bounds)
        dim.backgroundColor = .black
        dim.alpha = 0
        dim.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        dim.isUserInteractionEnabled = false
        blur.contentView.addSubview(dim)
        self.dim = dim
        UIView.animate(withDuration: Self.fadeDuration) { dim.alpha = ChatBackdrop.dimAlpha }

        let clip = UIView()
        clip.clipsToBounds = true
        clip.isUserInteractionEnabled = false
        // Stays in the host the menu blurred, above the whole screen the blur has moved into, so the
        // floated copy is the one thing over the composer — but still under the navigation bar.
        if let navigationBar, navigationBar.superview === host {
            host.insertSubview(clip, belowSubview: navigationBar)
        } else {
            host.addSubview(clip)
        }
        spotlightClip = clip

        layoutHeld()

        blur.isUserInteractionEnabled = true
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        blur.addGestureRecognizer(tap)
    }

    /// Re-measures a held blur, and the clip the floated copy lives in, which stops at the composer
    /// bar as it rises and falls with the keyboard. A no-op when nothing is held, so a layout pass
    /// outside an edit is harmless.
    func layoutHeld() {
        guard isHeld, let blur = effectView, let bar = clearance else { return }
        if let blurHost = blur.superview {
            blur.frame = blurHost.bounds
        }
        if let clip = spotlightClip, let clipHost = clip.superview {
            let barTop = bar.convert(bar.bounds, to: clipHost).minY
            clip.frame = CGRect(x: 0, y: 0, width: clipHost.bounds.width, height: max(barTop, 0))
        }
    }

    /// Floats `bubble` — a detached copy of the edited message — above a held blur, at `frame` in the
    /// coordinates of the host the blur was presented over.
    ///
    /// A copy rather than a hole cut in the blur: a `UIVisualEffectView` renders its backdrop
    /// through a private layer that ignores `layer.mask`, and the real bubble can't be raised out of
    /// the collection view that owns it. It goes in the clip rather than straight into the host, so
    /// it stops at the composer instead of covering it.
    func setSpotlight(_ bubble: UIView, at frame: CGRect) {
        guard isHeld, let clip = spotlightClip else { return }
        spotlight?.removeFromSuperview()
        bubble.frame = clampedToClip(frame)
        bubble.isUserInteractionEnabled = false
        clip.addSubview(bubble)
        spotlight = bubble
    }

    /// Whether a copy is currently floating.
    var hasSpotlight: Bool { spotlight != nil }

    /// Moves the floated copy as the keyboard and the bar reflow the transcript underneath it. A
    /// no-op when nothing is floating, so a layout pass before the copy exists is harmless.
    func moveSpotlight(to frame: CGRect) {
        spotlight?.frame = clampedToClip(frame)
    }

    /// Keeps a spotlight frame's bottom edge inside the clip instead of letting `clipsToBounds` cut
    /// the whole copy away. The clip's own bottom edge tracks the composer bar live, and the bar
    /// moves on its own animation as the keyboard returns after an edit is chosen — a beat where the
    /// transcript is still settling into its post-edit scroll position can put the copy's last known
    /// frame below the clip's already-shrunk bottom edge, which reads as the message disappearing
    /// rather than merely trailing the reflow. Clamping keeps it in view, hugging the composer, until
    /// the next reflow reports its true position.
    private func clampedToClip(_ frame: CGRect) -> CGRect {
        guard let clipHeight = spotlightClip?.bounds.height else { return frame }
        let maxY = clipHeight - frame.height
        guard maxY >= 0 else { return frame }
        var result = frame
        result.origin.y = min(frame.origin.y, maxY)
        return result
    }

    /// Fades the blur out and takes it off screen once it has gone, keeping a hole over `revealing`
    /// as it moves so a copy landing underneath stays sharp. A held blur ignores this: the edit it
    /// belongs to outlives the lift, and ends it with `release`.
    func dismiss(revealing view: UIView? = nil) {
        guard !isHeld, let blur = effectView else { return }
        effectView = nil
        let strength = blurStrength
        blurStrength = nil
        let hole = view.map { BlurHole(cutting: blur, around: $0) }

        UIView.animate(withDuration: Self.fadeDuration) {
            blur.alpha = 0
        } completion: { _ in
            hole?.stop()
            strength?.stopAnimation(true)
            blur.removeFromSuperview()
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
        let dim = self.dim
        self.dim = nil
        let strength = blurStrength
        blurStrength = nil
        UIView.animate(withDuration: Self.fadeDuration) {
            blur.alpha = 0
            bubble?.alpha = 0
            dim?.alpha = 0
        } completion: { _ in
            strength?.stopAnimation(true)
            blur.removeFromSuperview()
            clip?.removeFromSuperview()
        }
    }

    @objc private func handleTap() {
        onTap?()
    }
}

/// Masks a hole out of a blur over wherever `target` is drawn, frame by frame, so a view animating
/// underneath the blur shows through it unblurred.
@MainActor
private final class BlurHole {

    private static let cornerRadius: CGFloat = 18

    private weak var blur: UIView?
    private weak var target: UIView?
    private let shape = CAShapeLayer()
    private var link: CADisplayLink?

    init(cutting blur: UIView, around target: UIView) {
        self.blur = blur
        self.target = target
        let mask = UIView(frame: blur.bounds)
        shape.fillRule = .evenOdd
        shape.fillColor = UIColor.black.cgColor
        mask.layer.addSublayer(shape)
        blur.mask = mask
        update()
        let link = CADisplayLink(target: self, selector: #selector(update))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func update() {
        guard let blur, let target, let container = target.superview?.layer else { return stop() }
        let frame = container.convert(target.layer.presentation()?.frame ?? target.frame, to: blur.layer)
        let path = UIBezierPath(rect: blur.bounds)
        path.append(UIBezierPath(roundedRect: frame, cornerRadius: Self.cornerRadius))
        shape.path = path.cgPath
    }
}
#endif
