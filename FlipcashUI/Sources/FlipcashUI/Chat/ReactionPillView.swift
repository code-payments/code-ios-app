//
//  ReactionPillView.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit
import SwiftUI
import FlipcashCore

/// One reaction pill: emoji + count, capsule-shaped over the same wash a received bubble sits on.
/// A self-reacted pill draws a grey outline. Tap toggles the reaction; long-press opens the reactors sheet scoped to this
/// emoji — there is no cross-emoji "All" view to open instead.
final class ReactionPillView: UIView {

    private let stack = UIStackView()
    private let emojiLabel = UILabel()
    private let countLabel = UILabel()

    /// Fired on a plain tap. Nil (rather than swallowing the tap in `configure`) so a viewer who
    /// cannot react — a group previewer — still gets a working long-press.
    var onTap: (() -> Void)?
    var onLongPress: (() -> Void)?

    private(set) var pill: ReactionPill?
    /// The emoji this pill last drew, so the row can keep the pill across a reconfigure.
    var emoji: String { pill?.emoji ?? "" }

    private static let height: CGFloat = 28
    private static let horizontalPadding: CGFloat = 10
    private static let selfReactedFill = UIColor.white.withAlphaComponent(0.12)
    private static let restingFill = UIColor.white.withAlphaComponent(0.06)
    private static let selfReactedBorder = UIColor.white.withAlphaComponent(0.24)
    /// Android's `thickBorder`.
    private static let selfReactedBorderWidth: CGFloat = 2

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = Self.height / 2
        clipsToBounds = true

        stack.axis = .horizontal
        stack.spacing = 4
        stack.alignment = .center
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        emojiLabel.font = .systemFont(ofSize: 15)
        countLabel.font = .default(size: 13, weight: .medium)
        countLabel.textColor = UIColor(Color.textMain)
        stack.addArrangedSubview(emojiLabel)
        stack.addArrangedSubview(countLabel)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Self.height),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.horizontalPadding),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.horizontalPadding),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        addGestureRecognizer(tap)
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(longPressed))
        addGestureRecognizer(longPress)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// - Parameters:
    ///   - canReact: false withholds nothing here — the pill always draws and always opens the
    ///     reactors sheet on long-press. Only the tap-to-toggle is disabled, per spec (a group
    ///     previewer's tap is inert).
    ///   - animated: whether a change to a pill already on screen animates: the count rolls to its new
    ///     value and the selected fill and border fade.
    func configure(with pill: ReactionPill, canReact: Bool, animated: Bool = false) {
        let previous = self.pill
        self.pill = pill
        emojiLabel.text = pill.emoji
        if animated, let previous, previous.emoji == pill.emoji, previous.count != pill.count {
            rollCount(up: pill.count > previous.count)
        }
        countLabel.text = "\(pill.count)"

        let fill = pill.selfReacted ? Self.selfReactedFill : Self.restingFill
        let borderWidth = pill.selfReacted ? Self.selfReactedBorderWidth : 0
        if animated, let previous, previous.selfReacted != pill.selfReacted {
            let border = CABasicAnimation(keyPath: "borderWidth")
            border.fromValue = layer.presentation()?.borderWidth ?? layer.borderWidth
            border.toValue = borderWidth
            border.duration = ChatMotion.reactionChange.duration
            border.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(border, forKey: "borderWidth")
            ChatMotion.reactionChange.animate { self.backgroundColor = fill }
        } else {
            backgroundColor = fill
        }
        layer.borderColor = Self.selfReactedBorder.cgColor
        layer.borderWidth = borderWidth

        isUserInteractionEnabled = true
        isAccessibilityElement = true
        accessibilityLabel = "\(pill.emoji), \(pill.count) reaction\(pill.count == 1 ? "" : "s")"
        accessibilityTraits = canReact ? .button : []
    }

    /// Rolls the count to its next value: up for a rise, down for a fall, the way a counter turns.
    /// Reduce Motion gets a crossfade instead.
    private func rollCount(up: Bool) {
        let transition = CATransition()
        if UIAccessibility.isReduceMotionEnabled {
            transition.type = .fade
        } else {
            transition.type = .push
            transition.subtype = up ? .fromTop : .fromBottom
        }
        transition.duration = ChatMotion.reactionChange.duration
        transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        countLabel.layer.add(transition, forKey: "count")
    }

    @objc private func tapped() {
        onTap?()
    }

    @objc private func longPressed(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began else { return }
        onLongPress?()
    }
}
#endif
