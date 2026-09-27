//
//  LinkCardShimmerView.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit
import SwiftUI

/// A swept highlight over the part of a link card that is genuinely absent until its lookup lands.
///
/// Two shapes of the same thing. A *slot* draws its own ground, for a place on the card where the
/// answer will put something and there is nothing yet — a cash card's amount, its stub. A *surface*
/// draws none and only sweeps, for a place that is already painted with a stand-in and is waiting
/// to be repainted — a token card's bill, which is the neutral row colour until the mint's own
/// colours arrive.
///
/// It never covers text the card can already stand behind. A shimmer over a correct value tells the
/// reader it is a guess, and both card kinds say true things while unresolved: a cash card is
/// branded, a token card names the mint's address.
///
/// Sweeps only while it is in a window, so rows scrolled off the screen are not animating, and only
/// while the system allows motion — under Reduce Motion the ground stays and the sweep does not run.
final class LinkCardShimmerView: UIView {

    /// One pass of the highlight across the view.
    private static let period: CFTimeInterval = 1.15

    /// The highlight's share of the width. Narrow enough to read as a pass rather than as the view
    /// changing colour underneath the reader.
    private static let bandWidth: CGFloat = 0.22

    private static let animationKey = "shimmer"

    private let sweep = CAGradientLayer()

    /// Whether the card wants this shimmering. The sweep also needs a window and motion allowed —
    /// see ``updateSweep()``.
    private var isWanted = false
    /// Cuts the shimmer to a card's per-corner outline; nil while it rounds evenly or not at all.
    private var outline: (mask: CAShapeLayer, radii: RectangleCornerRadii)?

    /// - Parameters:
    ///   - ground: the slot's own fill, or nil for a surface that only sweeps.
    ///   - highlight: the colour the band passes in. Chosen against what it sweeps over, which is
    ///     the card's paper for a slot and the mint's stand-in ground for a surface.
    init(ground: UIColor?, highlight: UIColor) {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        backgroundColor = ground
        clipsToBounds = true

        sweep.startPoint = CGPoint(x: 0, y: 0.5)
        sweep.endPoint = CGPoint(x: 1, y: 0.5)
        sweep.colors = [
            highlight.withAlphaComponent(0).cgColor,
            highlight.cgColor,
            highlight.withAlphaComponent(0).cgColor,
        ]
        sweep.locations = [0, 0.5, 1]
        layer.addSublayer(sweep)

        // Core Animation drops a repeating animation when the app leaves the screen; a card still
        // waiting on its lookup when the reader comes back would otherwise sit frozen mid-pass.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Resized without an implicit animation, the way the token card's gradient is: a recycled
        // row's new bounds must not drag the band a frame behind them.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sweep.frame = bounds
        if let outline {
            outline.mask.frame = bounds
            outline.mask.path = BubbleBackgroundView.path(radii: outline.radii, in: bounds)
        }
        CATransaction.commit()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateSweep()
    }

    /// The radius of a slot's ground. Set by the card, which knows what the answer will put there.
    func roundCorners(to radius: CGFloat) {
        layer.cornerRadius = radius
        layer.cornerCurve = .continuous
    }

    /// The per-corner outline of a surface that stands in for a whole card, so the placeholder
    /// takes the same place in a bubble run as the card that replaces it.
    func roundCorners(to radii: RectangleCornerRadii) {
        let mask = outline?.mask ?? CAShapeLayer()
        layer.cornerRadius = 0
        layer.mask = mask
        outline = (mask, radii)
        setNeedsLayout()
    }

    /// Shows or hides the shimmer. Hidden rather than removed, so a recycled row that needs it
    /// again does not rebuild the layer.
    func setShimmering(_ shimmering: Bool) {
        isWanted = shimmering
        isHidden = !shimmering
        updateSweep()
    }

    @objc private func applicationDidBecomeActive() {
        updateSweep()
    }

    // Runs only when all three hold: the card wants it, the view is on screen, and the reader has
    // not asked for less motion. Under Reduce Motion a slot keeps its ground — the placeholder is
    // the information, and the sweep is only what draws the eye to it.
    private func updateSweep() {
        let shouldSweep = isWanted && window != nil && !UIAccessibility.isReduceMotionEnabled
        guard shouldSweep else {
            sweep.removeAnimation(forKey: Self.animationKey)
            sweep.isHidden = true
            return
        }
        sweep.isHidden = false
        guard sweep.animation(forKey: Self.animationKey) == nil else { return }

        let band = Double(Self.bandWidth)
        let animation = CABasicAnimation(keyPath: "locations")
        animation.fromValue = [-band * 2, -band, 0].map { NSNumber(value: $0) }
        animation.toValue = [1, 1 + band, 1 + band * 2].map { NSNumber(value: $0) }
        animation.duration = Self.period
        animation.repeatCount = .infinity
        sweep.add(animation, forKey: Self.animationKey)
    }
}
#endif
