//
//  ChatTypingIndicatorCell.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit
import FlipcashCore

/// Three dots in a leading incoming bubble, shown while the counterpart is typing. The bubble reuses
/// the shared `BubbleBackgroundView` chrome (incoming fill + hairline + 12pt radius), and the dots run
/// a repeating iMessage-style opacity wave — each brightens to `peakOpacity` in turn and settles back.
/// In a group, the typists' avatars overlap in a row ahead of the bubble.
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

    // Android's `TypingIndicator`: the transcript's 24pt sender avatar, overlapping by 8, with a 4pt
    // gap to the bubble and a 2pt ring cut out of each avatar beneath another.
    private static let avatarSize = ChatAuthorAvatarView.size
    private static let avatarOverlap: CGFloat = 8
    private static let avatarGap: CGFloat = 4
    private static let avatarRing: CGFloat = 2
    private static let avatarStep = avatarSize - avatarOverlap
    /// How small an avatar is as it starts to grow in, or finishes shrinking out.
    private static let avatarEnterScale: CGFloat = 0.4

    private let bubble = BubbleBackgroundView()
    private let dotsRow = UIStackView()
    private var dots: [UIView] = []

    private let avatarRow = UIView()
    private var avatarRowWidth: NSLayoutConstraint!
    /// Every avatar drawn, including ones still animating out after their typist left.
    private var entries: [AvatarEntry] = []
    /// The number of avatars the row's width is sized for, animated so the bubble slides.
    private var count = Spring(0)
    private var displayLink: CADisplayLink?
    private var lastTick: CFTimeInterval?
    /// False until the first configure after a dequeue, which draws its avatars in place.
    private var hasConfigured = false

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

        // A shrinking avatar draws past the row's animated width.
        avatarRow.clipsToBounds = false
        avatarRow.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(avatarRow)
        avatarRowWidth = avatarRow.widthAnchor.constraint(equalToConstant: 0)

        let trailing = bubble.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -12)
        trailing.priority = .defaultHigh
        NSLayoutConstraint.activate([
            avatarRow.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            avatarRow.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            avatarRow.heightAnchor.constraint(equalToConstant: Self.avatarSize),
            avatarRowWidth,
            bubble.topAnchor.constraint(equalTo: contentView.topAnchor),
            bubble.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            bubble.leadingAnchor.constraint(equalTo: avatarRow.trailingAnchor),
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

    public override func prepareForReuse() {
        super.prepareForReuse()
        stopAvatarMotion()
        entries.forEach { $0.view.removeFromSuperview() }
        entries = []
        count = Spring(0)
        hasConfigured = false
        layoutAvatars()
    }

    /// Draws the newest ``ChatItem/maxTypingAvatars`` of `typists` as an overlapping stack ahead of
    /// the dots, oldest at the back on the left and newest on top at the right, reading pictures out
    /// of `imageData`. An empty list draws the dots alone. Once the cell has been configured, a
    /// typist joining grows in from its left edge, one leaving shrinks out beneath the others as they
    /// slide over it, and the bubble slides with the stack's width.
    public func configure(typists: [ChatAuthor], imageData: [UserID: Data]) {
        let animated = hasConfigured && window != nil && !UIAccessibility.isReduceMotionEnabled
        hasConfigured = true
        let shown = Array(typists.suffix(ChatItem.maxTypingAvatars))
        let shownIDs = Set(shown.map(\.id))

        for (index, author) in shown.enumerated() {
            let slot = CGFloat(index)
            let entry: AvatarEntry
            if let existing = entries.first(where: { $0.id == author.id && !$0.isLeaving }) {
                entry = existing
            } else {
                let view = ChatAuthorAvatarView(frame: .zero)
                // Grows from and shrinks to its left edge, as Android's `TransformOrigin(0, 0.5)`.
                view.layer.anchorPoint = CGPoint(x: 0, y: 0.5)
                avatarRow.addSubview(view)
                entry = AvatarEntry(id: author.id, view: view, slot: Spring(slot), presence: Spring(animated ? 0 : 1))
                entries.append(entry)
            }
            entry.view.configure(with: author, imageData: imageData[author.id])
            entry.slot.target = slot
            entry.presence.target = 1
        }
        for entry in entries where !entry.isLeaving && !shownIDs.contains(entry.id) {
            entry.isLeaving = true
            entry.presence.target = 0
        }
        count.target = CGFloat(shown.count)

        if animated {
            startAvatarMotion()
        } else {
            stopAvatarMotion()
            entries.forEach { $0.settle() }
            count.settle()
            layoutAvatars()
        }
    }

    // MARK: - Avatar motion

    /// One avatar in the stack, kept after its typist leaves until it has animated out.
    private final class AvatarEntry {
        let id: UserID
        let view: ChatAuthorAvatarView
        let ring = CALayer()
        /// The avatar's horizontal place in the stack, in steps from the left.
        var slot: Spring
        /// 0 while absent, 1 once fully in: drives the avatar's alpha, scale and the ring it cuts.
        var presence: Spring
        var isLeaving = false

        init(id: UserID, view: ChatAuthorAvatarView, slot: Spring, presence: Spring) {
            self.id = id
            self.view = view
            self.slot = slot
            self.presence = presence
            view.layer.mask = ring
        }

        /// Later slots draw on top, and a leaving avatar beneath everything, so the ones that close
        /// the gap slide over it.
        var z: CGFloat { isLeaving ? -1 : slot.value }

        var scale: CGFloat {
            ChatTypingIndicatorCell.avatarEnterScale + (1 - ChatTypingIndicatorCell.avatarEnterScale) * presence.value
        }

        var isSettled: Bool { slot.isSettled && presence.isSettled }

        func settle() {
            slot.settle()
            presence.settle()
        }
    }

    /// A critically damped spring at Compose's `StiffnessMediumLow`, the `AvatarMotion` Android uses.
    private struct Spring {
        private static let stiffness: CGFloat = 400

        var value: CGFloat
        var target: CGFloat
        private var velocity: CGFloat = 0

        init(_ value: CGFloat) {
            self.value = value
            self.target = value
        }

        var isSettled: Bool { abs(value - target) < 0.001 && abs(velocity) < 0.01 }

        mutating func settle() {
            value = target
            velocity = 0
        }

        mutating func step(by elapsed: CFTimeInterval) {
            // Small fixed substeps keep the integration stable through a dropped frame.
            var remaining = CGFloat(min(elapsed, 1.0 / 15))
            while remaining > 0 {
                let dt = min(remaining, 1.0 / 240)
                let acceleration = -Self.stiffness * (value - target) - 2 * Self.stiffness.squareRoot() * velocity
                velocity += acceleration * dt
                value += velocity * dt
                remaining -= dt
            }
            if isSettled { settle() }
        }
    }

    private func startAvatarMotion() {
        guard displayLink == nil else { return }
        lastTick = nil
        let link = CADisplayLink(target: self, selector: #selector(stepAvatarMotion(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopAvatarMotion() {
        displayLink?.invalidate()
        displayLink = nil
        lastTick = nil
    }

    @objc private func stepAvatarMotion(_ link: CADisplayLink) {
        let elapsed = lastTick.map { link.timestamp - $0 } ?? link.duration
        lastTick = link.timestamp
        for entry in entries {
            entry.slot.step(by: elapsed)
            entry.presence.step(by: elapsed)
        }
        count.step(by: elapsed)

        for entry in entries where entry.isLeaving && entry.presence.isSettled {
            entry.view.removeFromSuperview()
        }
        entries.removeAll { $0.isLeaving && $0.presence.isSettled }
        layoutAvatars()

        if count.isSettled, entries.allSatisfy(\.isSettled) {
            stopAvatarMotion()
        }
    }

    /// Places every avatar and the row's width from the springs' current values, and recuts the
    /// rings each avatar shows where the ones above it sit.
    private func layoutAvatars() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        for entry in entries {
            entry.view.bounds = CGRect(x: 0, y: 0, width: Self.avatarSize, height: Self.avatarSize)
            entry.view.center = CGPoint(x: entry.slot.value * Self.avatarStep, y: Self.avatarSize / 2)
            entry.view.transform = CGAffineTransform(scaleX: entry.scale, y: entry.scale)
            entry.view.alpha = entry.presence.value
            entry.view.layer.zPosition = entry.z
            cutRings(in: entry)
        }

        // n avatars are n steps plus one overlap wide; the gap to the bubble grows in with the first
        // avatar, so the dots never jump.
        let count = max(count.value, 0)
        avatarRowWidth.constant = count * Self.avatarStep + (Self.avatarOverlap + Self.avatarGap) * min(count, 1)
        contentView.layoutIfNeeded()
    }

    /// Masks `entry` with a transparent ring wherever an avatar above it sits, faded by that avatar's
    /// presence, so overlapping faces stay apart over any background. Worked in the avatar's unscaled
    /// space, which is scaled about its left edge.
    private func cutRings(in entry: AvatarEntry) {
        let above = entries.filter { $0 !== entry && $0.z > entry.z && $0.presence.value > 0 }
        let size = CGSize(width: Self.avatarSize, height: Self.avatarSize)
        entry.ring.frame = CGRect(origin: .zero, size: size)
        guard !above.isEmpty else {
            entry.ring.contents = nil
            entry.ring.backgroundColor = UIColor.black.cgColor
            return
        }
        let radius = Self.avatarSize / 2
        let format = UIGraphicsImageRendererFormat.preferred()
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            cg.setFillColor(UIColor.black.cgColor)
            cg.fill(CGRect(origin: .zero, size: size))
            cg.setBlendMode(.destinationOut)
            for other in above {
                let centerX = (other.slot.value - entry.slot.value) * Self.avatarStep + radius * other.scale
                let cutRadius = (radius * other.scale + Self.avatarRing) / entry.scale
                let center = CGPoint(x: centerX / entry.scale, y: radius)
                cg.setFillColor(UIColor(white: 0, alpha: min(max(other.presence.value, 0), 1)).cgColor)
                cg.fillEllipse(in: CGRect(
                    x: center.x - cutRadius,
                    y: center.y - cutRadius,
                    width: cutRadius * 2,
                    height: cutRadius * 2
                ))
            }
        }
        entry.ring.backgroundColor = nil
        entry.ring.contents = image.cgImage
    }

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
        // Nothing is left to watch the avatars settle, so land them.
        if displayLink != nil {
            stopAvatarMotion()
            entries.filter(\.isLeaving).forEach { $0.view.removeFromSuperview() }
            entries.removeAll(where: \.isLeaving)
            entries.forEach { $0.settle() }
            count.settle()
            layoutAvatars()
        }
    }
}
#endif
