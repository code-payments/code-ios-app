//
//  ComposerFade.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import UIKit

/// The chat's bottom dissolve as a ramp of background opacities: clear for most of its height, then
/// a late rise that stops short of opaque, so content behind the bottom edge still shows faintly.
public enum ChatFade {

    private static let curve = UnitCurve.bezier(
        startControlPoint: UnitPoint(x: 0.42, y: 0.18),
        endControlPoint: UnitPoint(x: 0.17, y: 1.04)
    )
    private static let endOpacity = 0.9
    private static let samples = 32

    /// The ramp sampled top to bottom, as a location and the background's opacity there.
    static let stops: [(location: Double, opacity: Double)] = (0...samples).map {
        let location = Double($0) / Double(samples)
        return (location, endOpacity * curve.value(at: location))
    }

    /// The ramp in `color`, for a top-to-bottom gradient.
    public static func gradient(_ color: Color) -> Gradient {
        Gradient(stops: stops.map { .init(color: color.opacity($0.opacity), location: $0.location) })
    }
}

/// The dissolve from the transcript into the bottom of the screen: a ramp from nothing to the chat
/// background, starting at the bar's top edge and reaching full opacity only at the screen's bottom
/// edge, or the keyboard's top edge while one is up. The bar floats over it with no surface of its
/// own.
///
/// Core Animation rather than a hosted SwiftUI view, because its frame travels with the keyboard and
/// the reply strip: a gradient layer's stops are relative, so the ramp stretches with the animated
/// bounds instead of being drawn at the destination size and slid there.
@MainActor
final class ComposerFadeView: UIView {

    private let colorRamp = GradientView()

    init() {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        addSubview(colorRamp)
        let base = UIColor(Color.backgroundMain)
        colorRamp.set(
            colors: ChatFade.stops.map { base.withAlphaComponent($0.opacity) },
            locations: ChatFade.stops.map { NSNumber(value: $0.location) }
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        colorRamp.frame = bounds
    }
}

/// A view backed by a top-to-bottom gradient layer.
private final class GradientView: UIView {

    override class var layerClass: AnyClass { CAGradientLayer.self }

    private var gradient: CAGradientLayer { layer as! CAGradientLayer }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        gradient.startPoint = CGPoint(x: 0.5, y: 0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func set(colors: [UIColor], locations: [NSNumber]) {
        gradient.colors = colors.map(\.cgColor)
        gradient.locations = locations
    }
}
