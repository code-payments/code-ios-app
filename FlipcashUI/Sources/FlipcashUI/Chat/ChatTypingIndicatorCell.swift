//
//  ChatTypingIndicatorCell.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit

/// Three dots in a leading incoming bubble, shown while the counterpart is typing. The bubble reuses
/// the shared `BubbleBackgroundView` chrome (incoming fill + hairline + 12pt radius), and the dots run
/// a repeating iMessage-style opacity wave — each brightens to `peakOpacity` in turn and settles back.
public final class ChatTypingIndicatorCell: UICollectionViewCell {

    public static let reuseIdentifier = "ChatTypingIndicatorCell"

    // ── tuning knobs ──────────────────────────────────────────────────
    /// Resting dot opacity (the design's static state: white @ 30%).
    private static let baseOpacity: Double = 0.3
    /// Opacity a dot rises to as the wave passes through it.
    private static let peakOpacity: Double = 0.85
    /// One full wave cycle, including the rest before it repeats.
    private static let wavePeriod: Double = 1.3
    /// Gap between neighbouring dots' rises — the wave's left-to-right speed.
    private static let waveStagger: Double = 0.16
    /// How long a dot takes to brighten, and to settle back down.
    private static let dotRise: Double = 0.20
    private static let dotFall: Double = 0.30
    /// Beat after the cycle starts before the first dot rises.
    private static let waveLeadIn: Double = 0.20
    // ──────────────────────────────────────────────────────────────────

    private static let dotSize: CGFloat = 7

    private let bubble = BubbleBackgroundView()
    private let dotsRow = UIStackView()
    private var dots: [UIView] = []

    public override init(frame: CGRect) {
        super.init(frame: frame)

        bubble.apply(
            fill: BubbleBackgroundView.fill(isFromSelf: false),
            radii: BubbleBackgroundView.radii(isFromSelf: false, groupedAbove: false, groupedBelow: false)
        )
        bubble.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(bubble)

        dotsRow.axis = .horizontal
        dotsRow.spacing = 4
        dotsRow.alignment = .center
        dotsRow.translatesAutoresizingMaskIntoConstraints = false
        bubble.addSubview(dotsRow)
        dots = (0..<3).map { _ in
            let dot = UIView()
            dot.backgroundColor = .white
            dot.layer.cornerRadius = Self.dotSize / 2
            dot.layer.opacity = Float(Self.baseOpacity)
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.widthAnchor.constraint(equalToConstant: Self.dotSize).isActive = true
            dot.heightAnchor.constraint(equalToConstant: Self.dotSize).isActive = true
            dotsRow.addArrangedSubview(dot)
            return dot
        }

        let trailing = bubble.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -12)
        trailing.priority = .defaultHigh
        NSLayoutConstraint.activate([
            bubble.topAnchor.constraint(equalTo: contentView.topAnchor),
            bubble.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            bubble.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            trailing,
            // The bubble's own padding matches a text bubble's 12/9, plus the dot row's inner 6 vertical.
            dotsRow.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 12),
            dotsRow.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -12),
            dotsRow.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 15),
            dotsRow.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -15),
        ])

        // Returning from background strips a layer's animations; restart the wave on foreground.
        NotificationCenter.default.addObserver(self, selector: #selector(restartAnimationIfVisible), name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func restartAnimationIfVisible() {
        if window != nil { startAnimating() }
    }

    /// Start the dot wave. Driven by the collection view's `willDisplay` (not the cell's
    /// `didMoveToWindow`, which doesn't reliably re-fire across reuse): a recycled cell loses its
    /// `CAAnimation`s, so the wave must restart on every (re)display. Idempotent — re-adding under the
    /// same key replaces any prior copy. Each dot holds at base opacity until the wave reaches it,
    /// brightens, settles back, then rests until the cycle repeats; all three share `wavePeriod`, so
    /// the wave stays in phase across the row.
    public func startAnimating() {
        for (index, dot) in dots.enumerated() {
            let delay = Self.waveLeadIn + Double(index) * Self.waveStagger
            let peak = delay + Self.dotRise
            let settle = peak + Self.dotFall

            let wave = CAKeyframeAnimation(keyPath: "opacity")
            wave.values = [Self.baseOpacity, Self.baseOpacity, Self.peakOpacity, Self.baseOpacity, Self.baseOpacity]
            wave.keyTimes = [0, delay / Self.wavePeriod, peak / Self.wavePeriod, settle / Self.wavePeriod, 1].map { NSNumber(value: $0) }
            wave.timingFunctions = [
                CAMediaTimingFunction(name: .linear),
                CAMediaTimingFunction(name: .easeInEaseOut),
                CAMediaTimingFunction(name: .easeInEaseOut),
                CAMediaTimingFunction(name: .linear),
            ]
            wave.duration = Self.wavePeriod
            wave.repeatCount = .infinity
            dot.layer.add(wave, forKey: "typingWave")
        }
    }

    /// Stop the dot wave — the cell is leaving the screen.
    public func stopAnimating() {
        dots.forEach { $0.layer.removeAnimation(forKey: "typingWave") }
    }
}
#endif
