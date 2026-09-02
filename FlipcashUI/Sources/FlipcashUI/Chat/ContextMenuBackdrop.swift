//
//  ContextMenuBackdrop.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit

/// The blur that sits behind a message context menu.
///
/// UIKit only dims the content behind a context menu, leaving every bubble legible under the
/// platter. WhatsApp — the reference for this interaction — blurs it, so the lifted bubble is the
/// one sharp thing on screen. The blur covers whichever view it is presented over, and UIKit puts
/// the menu itself in a container above the window's root, so the platter and the lift stay sharp.
@MainActor
final class ContextMenuBackdrop {

    /// Matches the fade UIKit uses for its own dimming when no animator is supplied.
    private static let fallbackDuration: TimeInterval = 0.2

    private let effect = UIBlurEffect(style: .systemUltraThinMaterialDark)
    private var effectView: UIVisualEffectView?

    /// Fades the blur in over `host`, riding `animator` so it lands with the menu. Presenting twice
    /// is a no-op: the display callback fires once for the lift and again for the menu.
    func present(over host: UIView, animator: UIContextMenuInteractionAnimating?) {
        guard effectView == nil else { return }

        let blur = UIVisualEffectView(effect: nil)
        // Purely decorative — the menu's own container sits above this and owns every touch.
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

    /// Fades the blur out with the menu and takes it off screen once it has gone.
    func dismiss(animator: UIContextMenuInteractionAnimating?) {
        guard let blur = effectView else { return }
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
}
#endif
