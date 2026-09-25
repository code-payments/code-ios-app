//
//  ReactionStripView.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit
import FlipcashCore

/// The row of emoji offered above a long-pressed bubble, alongside the existing `UIMenu`, on a
/// Liquid Glass capsule. The emoji scroll sideways under the trailing "+", which stays pinned and
/// fades the row out beneath it. Tapping an emoji toggles the reaction and dismisses the menu; "+"
/// dismisses and opens the picker instead.
///
/// A plain view, not a context-menu preview accessory — `UIContextMenuConfiguration` has no slot for
/// one, and the menu's container already sits above the window root (see
/// `ChatScreenViewController.handOffComposerFocusAroundContextMenu`), so this is added as a sibling
/// above that container instead, positioned over the lifted bubble's frame.
final class ReactionStripView: UIView {

    /// Fired with the tapped emoji.
    var onSelect: ((String) -> Void)?
    var onAdd: (() -> Void)?

    // Sizes from the strip in node 9779:105563.
    static let height: CGFloat = 55
    static let maxWidth: CGFloat = 313
    private static let itemSize: CGFloat = 40
    private static let itemSpacing: CGFloat = 4
    private static let inset: CGFloat = 8
    private static let addSize: CGFloat = 38
    /// How far the fade reaches left of the "+" before the row is fully drawn.
    private static let fadeLead: CGFloat = 28

    private let surface: UIView
    /// Holds the fade mask; on the scroll view itself the mask would ride its moving bounds.
    private let fadeHost = UIView()
    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let addButton = UIButton(type: .system)
    private let fade = CAGradientLayer()

    override init(frame: CGRect) {
        if #available(iOS 26, *) {
            let glass = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
            glass.cornerConfiguration = .capsule()
            surface = glass
        } else {
            surface = UIView()
            surface.backgroundColor = UIColor(red: 0x30 / 255, green: 0x30 / 255, blue: 0x30 / 255, alpha: 1)
            surface.layer.cornerRadius = Self.height / 2
            surface.layer.cornerCurve = .continuous
            surface.clipsToBounds = true
        }
        super.init(frame: frame)

        let content = (surface as? UIVisualEffectView)?.contentView ?? surface
        surface.translatesAutoresizingMaskIntoConstraints = false
        addSubview(surface)

        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        // Room to bring the last emoji out from under the "+" and its fade.
        scrollView.contentInset = UIEdgeInsets(
            top: 0, left: Self.inset, bottom: 0,
            right: Self.inset + Self.addSize + Self.fadeLead
        )
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        fadeHost.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(fadeHost)
        fadeHost.addSubview(scrollView)

        fade.startPoint = CGPoint(x: 0, y: 0.5)
        fade.endPoint = CGPoint(x: 1, y: 0.5)
        // Clear at the leading inset too, so scrolled-past emoji don't poke out of the capsule's curve.
        fade.colors = [UIColor.clear.cgColor, UIColor.black.cgColor, UIColor.black.cgColor, UIColor.clear.cgColor, UIColor.clear.cgColor]
        fadeHost.layer.mask = fade

        stack.axis = .horizontal
        // Centered rather than filled, so each emoji keeps its square frame and its highlight stays a circle.
        stack.alignment = .center
        stack.spacing = Self.itemSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        if #available(iOS 26, *) {
            var configuration = UIButton.Configuration.glass()
            configuration.image = .asset(.addReaction)
            configuration.cornerStyle = .capsule
            configuration.contentInsets = .zero
            addButton.configuration = configuration
        } else {
            addButton.setImage(.asset(.addReaction), for: .normal)
            addButton.backgroundColor = UIColor.white.withAlphaComponent(0.18)
            addButton.layer.cornerRadius = Self.addSize / 2
            addButton.clipsToBounds = true
        }
        addButton.translatesAutoresizingMaskIntoConstraints = false
        addButton.addTarget(self, action: #selector(addTapped), for: .touchUpInside)
        addButton.accessibilityLabel = "More reactions"
        content.addSubview(addButton)

        let fullWidth = scrollView.contentInset.left + scrollView.contentInset.right
        NSLayoutConstraint.activate([
            surface.leadingAnchor.constraint(equalTo: leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: trailingAnchor),
            surface.topAnchor.constraint(equalTo: topAnchor),
            surface.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: Self.height),
            widthAnchor.constraint(lessThanOrEqualToConstant: Self.maxWidth),

            fadeHost.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            fadeHost.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            fadeHost.topAnchor.constraint(equalTo: content.topAnchor),
            fadeHost.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: fadeHost.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: fadeHost.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: fadeHost.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: fadeHost.bottomAnchor),

            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
            // Grows to fit the entries up to `maxWidth`; past that the caller's edges win and the
            // rest scrolls under the "+".
            {
                let fit = scrollView.frameLayoutGuide.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: fullWidth)
                fit.priority = .defaultHigh
                return fit
            }(),

            addButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -Self.inset),
            addButton.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            addButton.widthAnchor.constraint(equalToConstant: Self.addSize),
            addButton.heightAnchor.constraint(equalToConstant: Self.addSize),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = fadeHost.bounds.width
        guard width > 0 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fade.frame = fadeHost.bounds
        let clearFrom = width - Self.inset - Self.addSize / 2
        let solidUntil = width - Self.inset - Self.addSize - Self.fadeLead
        fade.locations = [0, Self.inset / width, solidUntil / width, clearFrom / width, 1].map { NSNumber(value: Double($0)) }
        CATransaction.commit()
    }

    func configure(entries: [ReactionStrip.Entry]) {
        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        for entry in entries {
            let button = UIButton(type: .system)
            button.setTitle(entry.emoji, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 28)
            button.backgroundColor = entry.highlighted ? UIColor.white.withAlphaComponent(0.18) : .clear
            button.layer.cornerRadius = Self.itemSize / 2
            button.clipsToBounds = true
            button.widthAnchor.constraint(equalToConstant: Self.itemSize).isActive = true
            button.heightAnchor.constraint(equalToConstant: Self.itemSize).isActive = true
            button.addAction(UIAction { [weak self] _ in self?.onSelect?(entry.emoji) }, for: .touchUpInside)
            button.accessibilityLabel = entry.emoji
            stack.addArrangedSubview(button)
        }
        scrollView.contentOffset = CGPoint(x: -Self.inset, y: 0)
    }

    /// Pops the emoji in one after another, starting from the side the strip grows out of. Only the
    /// ones in view animate; the rest are already in place for when the row is scrolled.
    func revealEntries(fromTrailing: Bool) {
        let visible = scrollView.bounds
        let buttons = stack.arrangedSubviews.filter {
            $0.convert($0.bounds, to: scrollView).intersects(visible)
        }
        for (index, button) in (fromTrailing ? buttons.reversed() : buttons).enumerated() {
            button.transform = CGAffineTransform(scaleX: 0.2, y: 0.2)
            button.alpha = 0
            UIView.animate(
                withDuration: 0.35, delay: 0.03 * Double(index),
                usingSpringWithDamping: 0.6, initialSpringVelocity: 0
            ) {
                button.transform = .identity
                button.alpha = 1
            }
        }
    }

    @objc private func addTapped() {
        onAdd?()
    }
}
#endif
