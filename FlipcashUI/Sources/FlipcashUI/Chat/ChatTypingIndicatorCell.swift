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

    // Android's `staticGrid.x8` / `staticGrid.x4` (the fixed 5pt grid) and `grid.x2` on a phone.
    private static let avatarSize: CGFloat = 40
    private static let avatarOverlap: CGFloat = 20
    private static let avatarRowGap: CGFloat = 10
    /// Android pads the avatar row 4dp above and below.
    private static let avatarRowInset: CGFloat = 4

    private let bubble = BubbleBackgroundView()
    private let dotsRow = UIStackView()
    private var dots: [UIView] = []

    private let avatarRow = UIView()
    private var avatarRowWidth: NSLayoutConstraint!
    private var avatarRowHeight: NSLayoutConstraint!
    /// The avatars on screen, oldest typist first — the order they are drawn left to right.
    private var avatars: [(id: UserID, view: ChatAuthorAvatarView)] = []

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

        // Overlapping avatars draw past each other's bounds, and one fading out draws past the row's.
        avatarRow.clipsToBounds = false
        avatarRow.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(avatarRow)
        avatarRowWidth = avatarRow.widthAnchor.constraint(equalToConstant: 0)
        // The row only claims height while it holds avatars, so a DM's cell stays the bubble's height.
        avatarRowHeight = contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 0)

        let trailing = bubble.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -12)
        trailing.priority = .defaultHigh
        NSLayoutConstraint.activate([
            avatarRow.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            avatarRow.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            avatarRow.heightAnchor.constraint(equalToConstant: Self.avatarSize),
            avatarRowWidth,
            avatarRowHeight,
            bubble.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor),
            bubble.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor),
            bubble.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
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
        avatars.forEach { $0.view.removeFromSuperview() }
        avatars = []
        applyRowSize(count: 0)
    }

    /// Draws `typists` as overlapping avatars ahead of the dots, oldest first, reading their pictures
    /// out of `imageData`. An empty list draws the dots alone. A reconfigure of the same cell animates
    /// the avatars that joined or left and the row's width; the first configure after a dequeue
    /// snaps, since the row itself is animating in.
    public func configure(typists: [ChatAuthor], imageData: [UserID: Data]) {
        let animated = window != nil && !avatars.isEmpty
        let shown = Array(typists.suffix(ChatItem.maxTypingAvatars))
        let keep = Set(shown.map(\.id))

        let leaving = avatars.filter { !keep.contains($0.id) }
        var existing: [UserID: ChatAuthorAvatarView] = [:]
        for avatar in avatars where keep.contains(avatar.id) {
            existing[avatar.id] = avatar.view
        }

        var joining: [ChatAuthorAvatarView] = []
        avatars = shown.map { author in
            let view: ChatAuthorAvatarView
            if let kept = existing[author.id] {
                view = kept
            } else {
                view = ChatAuthorAvatarView(size: Self.avatarSize, fallback: .personGlyph)
                view.translatesAutoresizingMaskIntoConstraints = true
                self.avatarRow.addSubview(view)
                joining.append(view)
            }
            view.configure(with: author, imageData: imageData[author.id])
            return (id: author.id, view: view)
        }

        // New avatars start where they will land, so they only fade and grow in place.
        for (index, avatar) in avatars.enumerated() {
            // The earlier typist sits on top, as Android's `zIndex = count - index` does.
            avatar.view.layer.zPosition = CGFloat(avatars.count - index)
            if joining.contains(where: { $0 === avatar.view }) {
                avatar.view.frame = Self.avatarFrame(at: index)
                if animated {
                    avatar.view.alpha = 0
                    avatar.view.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
                }
            }
        }

        let layout = {
            for (index, avatar) in self.avatars.enumerated() {
                avatar.view.bounds.size = CGSize(width: Self.avatarSize, height: Self.avatarSize)
                avatar.view.center = CGPoint(
                    x: Self.avatarFrame(at: index).midX,
                    y: Self.avatarSize / 2
                )
                avatar.view.alpha = 1
                avatar.view.transform = .identity
            }
            for avatar in leaving {
                avatar.view.alpha = 0
                avatar.view.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
            }
            self.applyRowSize(count: self.avatars.count)
            self.contentView.layoutIfNeeded()
        }

        guard animated else {
            leaving.forEach { $0.view.removeFromSuperview() }
            UIView.performWithoutAnimation(layout)
            return
        }
        UIView.animate(
            withDuration: 0.35,
            delay: 0,
            usingSpringWithDamping: 1,
            initialSpringVelocity: 0,
            options: [.beginFromCurrentState, .allowUserInteraction],
            animations: layout,
            completion: { _ in leaving.forEach { $0.view.removeFromSuperview() } }
        )
    }

    private static func avatarFrame(at index: Int) -> CGRect {
        CGRect(
            x: CGFloat(index) * (avatarSize - avatarOverlap),
            y: 0,
            width: avatarSize,
            height: avatarSize
        )
    }

    private func applyRowSize(count: Int) {
        guard count > 0 else {
            avatarRowWidth.constant = 0
            avatarRowHeight.constant = 0
            return
        }
        avatarRowWidth.constant = Self.avatarSize + CGFloat(count - 1) * (Self.avatarSize - Self.avatarOverlap) + Self.avatarRowGap
        avatarRowHeight.constant = Self.avatarSize + 2 * Self.avatarRowInset
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
    }
}
#endif
