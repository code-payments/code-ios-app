//
//  JumpToBottomButton.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import SwiftUI
import UIKit
import FlipcashCore

/// A 44pt glass circle with a chevron and an unread badge that scrolls the transcript to its newest
/// message. White 12% over the chat's frosting, a hairline in the row-separator white, and a soft
/// shadow.
@MainActor
final class JumpToBottomButton: UIControl {

    static let diameter: CGFloat = 44

    private let blur = UIVisualEffectView()
    private let badge = BadgeView()
    private var blurStrength: UIViewPropertyAnimator?

    init() {
        super.init(frame: .zero)
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowRadius = 8
        layer.shadowOffset = CGSize(width: 0, height: 2)

        let disc = UIView()
        disc.translatesAutoresizingMaskIntoConstraints = false
        disc.isUserInteractionEnabled = false
        disc.clipsToBounds = true
        disc.layer.cornerRadius = Self.diameter / 2
        disc.layer.borderWidth = 0.5
        disc.layer.borderColor = UIColor(Color.rowSeparator).cgColor
        addSubview(disc)

        let tint = UIView()
        tint.translatesAutoresizingMaskIntoConstraints = false
        tint.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        blur.translatesAutoresizingMaskIntoConstraints = false
        disc.addSubview(blur)
        disc.addSubview(tint)
        blurStrength = ChatBackdrop.frost(blur)

        let chevron = UIImageView(image: UIImage(
            systemName: "chevron.down",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        ))
        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.tintColor = .white
        chevron.contentMode = .center
        chevron.isUserInteractionEnabled = false
        addSubview(chevron)

        badge.translatesAutoresizingMaskIntoConstraints = false
        addSubview(badge)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.diameter),
            heightAnchor.constraint(equalToConstant: Self.diameter),
            disc.topAnchor.constraint(equalTo: topAnchor),
            disc.bottomAnchor.constraint(equalTo: bottomAnchor),
            disc.leadingAnchor.constraint(equalTo: leadingAnchor),
            disc.trailingAnchor.constraint(equalTo: trailingAnchor),
            blur.topAnchor.constraint(equalTo: disc.topAnchor),
            blur.bottomAnchor.constraint(equalTo: disc.bottomAnchor),
            blur.leadingAnchor.constraint(equalTo: disc.leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: disc.trailingAnchor),
            tint.topAnchor.constraint(equalTo: disc.topAnchor),
            tint.bottomAnchor.constraint(equalTo: disc.bottomAnchor),
            tint.leadingAnchor.constraint(equalTo: disc.leadingAnchor),
            tint.trailingAnchor.constraint(equalTo: disc.trailingAnchor),
            chevron.centerXAnchor.constraint(equalTo: centerXAnchor),
            chevron.centerYAnchor.constraint(equalTo: centerYAnchor),
            // The pill's centre sits near the circle's top-trailing corner, pulled in along the arc.
            badge.centerXAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            badge.centerYAnchor.constraint(equalTo: topAnchor, constant: 4),
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = "Jump to latest message"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    isolated deinit {
        blurStrength?.stopAnimation(true)
    }

    /// Sets the badge from `count`; the badge hides at zero.
    func setUnreadCount(_ count: Int) {
        let text = UnreadBadgeText.text(for: count)
        badge.isHidden = text == nil
        badge.text = text
        accessibilityValue = text
    }

    /// The badge overhangs the circle's corner; a tap on the overhang is a tap on the button.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        super.point(inside: point, with: event) || (!badge.isHidden && badge.frame.contains(point))
    }

    /// The pill: blue fill (18pt tall inside the ring), white semibold 11, and a 2pt ring in the chat
    /// background that separates it from the circle.
    private final class BadgeView: UIView {
        private let label = UILabel()

        var text: String? {
            get { label.text }
            set { label.text = newValue }
        }

        init() {
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            isHidden = true
            backgroundColor = UIColor(Color.badgeFocus)
            layer.borderWidth = 2
            layer.borderColor = UIColor(Color.backgroundMain).cgColor
            label.translatesAutoresizingMaskIntoConstraints = false
            label.font = .systemFont(ofSize: 11, weight: .semibold)
            label.textColor = .white
            addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: centerXAnchor),
                label.centerYAnchor.constraint(equalTo: centerYAnchor),
                widthAnchor.constraint(greaterThanOrEqualTo: heightAnchor),
                heightAnchor.constraint(equalToConstant: 22),
                label.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 5),
                label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -5),
            ])
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func layoutSubviews() {
            super.layoutSubviews()
            layer.cornerRadius = bounds.height / 2
        }
    }
}
#endif
