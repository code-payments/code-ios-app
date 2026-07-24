//
//  BackdropBlur.swift
//  Flipcash
//

import SwiftUI
import UIKit

/// A backdrop Gaussian blur with an explicit radius.
///
/// `Material` blurs are fixed, system-calibrated, and tinted, so they can't hit
/// a design's exact blur value. This retargets UIKit's own backdrop filter to a
/// specific Gaussian radius and hides the adaptive tint, leaving a pure blur for
/// a caller to layer its own tint over.
struct BackdropBlur: UIViewRepresentable {

    /// Gaussian radius in points. A design tool's "Uniform N" blur is ~2·sigma,
    /// so a Figma value of N maps to `radius = N / 2` here (Uniform 40 → 20).
    var radius: CGFloat

    func makeUIView(context: Context) -> BackdropView { BackdropView() }

    func updateUIView(_ view: BackdropView, context: Context) {
        view.radius = radius
    }

    final class BackdropView: UIView {
        private let effectView = UIVisualEffectView(effect: UIBlurEffect(style: .regular))

        var radius: CGFloat = 0 {
            didSet { applyBlur() }
        }

        override init(frame: CGRect) {
            super.init(frame: frame)
            effectView.frame = bounds
            effectView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            addSubview(effectView)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        // The filter list only exists once the effect view is attached to a
        // window, so re-apply then rather than relying solely on the `radius`
        // setter firing before layout.
        override func didMoveToWindow() {
            super.didMoveToWindow()
            applyBlur()
        }

        // The backdrop subview carries the system's `gaussianBlur` filter;
        // overriding `inputRadius` retargets it, and fading the sibling tint
        // overlay leaves only the blur. Failing gracefully here degrades to the
        // default `.regular` blur rather than crashing if UIKit internals shift.
        private func applyBlur() {
            guard let backdrop = effectView.subviews.first else { return }
            for case let filter as NSObject in backdrop.layer.filters ?? [] {
                guard filter.value(forKey: "name") as? String == "gaussianBlur" else { continue }
                filter.setValue(radius, forKey: "inputRadius")
            }
            effectView.subviews.dropFirst().forEach { $0.alpha = 0 }
        }
    }
}
