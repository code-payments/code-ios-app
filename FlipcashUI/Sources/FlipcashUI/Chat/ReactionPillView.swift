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

/// One reaction pill: emoji + count on a capsule. A self-reacted pill takes the accent's tint, ring
/// and count colour; the ring never changes its width. Tap toggles the reaction; the row it
/// sits in owns the long press, so a press just off the pill still opens the reactors sheet.
final class ReactionPillView: UIView {

    private let stack = UIStackView()
    private let emojiLabel = UILabel()
    private let countLabel = UILabel()
    /// Holds the count label at the width its reserved digits need, so a count change inside that
    /// room never resizes the pill.
    private lazy var countWidth = countLabel.widthAnchor.constraint(equalToConstant: Self.countWidth(digits: 2))

    /// Fired on a plain tap. Nil (rather than swallowing the tap in `configure`) so a viewer who
    /// cannot react — a group previewer — still gets the row's long press.
    var onTap: (() -> Void)?

    private(set) var pill: ReactionPill?
    /// The emoji this pill last drew, so the row can keep the pill across a reconfigure.
    var emoji: String { pill?.emoji ?? "" }

    private static var selfReactedFill: UIColor { ChatStyle.accentTint }
    private static var restingFill: UIColor { ChatStyle.pillFill }
    private static var selfReactedBorder: UIColor { ChatStyle.accentRing }
    private static var selfReactedBorderWidth: CGFloat { ChatStyle.pillRingWidth }

    private lazy var heightConstraint = heightAnchor.constraint(equalToConstant: ChatStyle.pillHeight)
    private lazy var stackLeading = stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: ChatStyle.pillLeadingPadding)
    private lazy var stackTrailing = stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -ChatStyle.pillTrailingPadding)

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true

        stack.axis = .horizontal
        stack.spacing = ChatStyle.pillInnerGap
        stack.alignment = .center
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        countLabel.textAlignment = .left
        stack.addArrangedSubview(emojiLabel)
        stack.addArrangedSubview(countLabel)

        NSLayoutConstraint.activate([
            heightConstraint,
            stackLeading,
            stackTrailing,
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            countWidth,
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        addGestureRecognizer(tap)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// - Parameters:
    ///   - canReact: false withholds nothing here — the pill always draws, and the row's long press
    ///     still opens the reactors sheet. Only the tap-to-toggle is disabled, per spec (a group
    ///     previewer's tap is inert).
    ///   - countDigits: the digits of room the count keeps, which sets the pill's width.
    ///   - animated: whether a change to a pill already on screen animates: the count rolls to its new
    ///     value and the selected fill and border fade.
    func configure(with pill: ReactionPill, countDigits: Int = 2, canReact: Bool, animated: Bool = false) {
        let previous = self.pill
        self.pill = pill
        applyMetrics()
        emojiLabel.text = pill.emoji
        if animated, let previous, previous.emoji == pill.emoji, previous.count != pill.count {
            rollCount(up: pill.count > previous.count)
        }
        countLabel.text = "\(pill.count)"
        countWidth.constant = Self.countWidth(digits: max(min(countDigits, ChatStyle.pillCountRoom), "\(pill.count)".count)) // LOCAL-TUNER

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
        countLabel.textColor = pill.selfReacted ? ChatStyle.accentColor : ChatStyle.secondaryText

        isUserInteractionEnabled = true
        isAccessibilityElement = true
        accessibilityLabel = "\(pill.emoji), \(pill.count) reaction\(pill.count == 1 ? "" : "s")"
        accessibilityTraits = canReact ? .button : []
    }

    /// The width `digits` digits of the count font can take, whichever digits they are.
    static func countWidth(digits: Int) -> CGFloat {
        ceil(widestDigit * CGFloat(digits))
    }

    private static var countFont: UIFont { .default(size: ChatStyle.pillCountSize, weight: .semibold) }
    private static var widestDigit: CGFloat {
        let font = countFont
        return (0...9)
            .map { ("\($0)" as NSString).size(withAttributes: [.font: font]).width }
            .max() ?? 0
    }

    /// Sets the pill's size, paddings and type from `ChatStyle`.
    private func applyMetrics() {
        let height = ChatStyle.pillHeight
        stack.spacing = ChatStyle.pillInnerGap
        heightConstraint.constant = height
        layer.cornerRadius = height / 2
        stackLeading.constant = ChatStyle.pillLeadingPadding
        stackTrailing.constant = -ChatStyle.pillTrailingPadding
        emojiLabel.font = .systemFont(ofSize: ChatStyle.pillEmojiSize)
        countLabel.font = Self.countFont
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
}
#endif
