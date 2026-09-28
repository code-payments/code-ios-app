//
//  ReactionStripView.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit
import FlipcashCore

/// The row of emoji offered above a long-pressed or double-tapped bubble, on a Liquid Glass capsule.
/// The emoji scroll sideways toward the trailing "+", which stays pinned; each edge fades only while
/// there is more of the row to scroll to on that side. Tapping an emoji toggles the reaction and
/// dismisses the strip; "+" dismisses and opens the picker instead.
///
/// A plain view, not a context-menu preview accessory — `UIContextMenuConfiguration` has no slot for
/// one, and the menu's container already sits above the window root (see
/// `ChatScreenViewController.handOffComposerFocusAroundContextMenu`), so this is added as a sibling
/// above that container instead, positioned over the lifted bubble's frame.
final class ReactionStripView: UIView, UIScrollViewDelegate {

    /// Fired with the tapped emoji.
    var onSelect: ((String) -> Void)?
    var onAdd: (() -> Void)?

    // Sizes from the strip in node 9779:105563. Android's `QuickReactionStrip` uses the same values.
    static let height: CGFloat = 55
    static let maxWidth: CGFloat = 313
    /// The space between the strip and the lifted bubble it sits above.
    static let bubbleGap: CGFloat = 16
    /// The room a lifted bubble keeps above itself for the strip.
    static let headroom: CGFloat = height + bubbleGap
    private static let itemSize: CGFloat = 40
    private static let itemSpacing: CGFloat = 4
    private static let inset: CGFloat = 8
    private static let addSize: CGFloat = 40
    /// How far the leading fade reaches in from the edge, and how much scroll either fade takes to
    /// grow in, so neither snaps on.
    private static let edgeFade: CGFloat = 20
    /// The trailing fade's run, from the middle of the "+" to where its circle is last as tall as an
    /// emoji. Past that the row is hidden, so no emoji shows around the circle's curve.
    private static let trailingFade: CGFloat = 14
    private static let emojiFont = UIFont.systemFont(ofSize: 28)

    private let surface: UIView
    /// Holds the fade mask; on the scroll view itself the mask would ride its moving bounds.
    private let fadeHost = UIView()
    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let addButton = UIButton(type: .system)
    private let fade = CAGradientLayer()
    /// Set by `configure`, so the next layout pass scrolls the row to its leading end once the
    /// content has a size.
    private var needsRestingOffset = false

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
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.delegate = self
        // Scrolled to the end, the last emoji stops `itemSpacing` short of the "+".
        let plusSide = Self.inset + Self.addSize + Self.itemSpacing
        scrollView.contentInset = UIEdgeInsets(
            top: 0, left: isRightToLeft ? plusSide : Self.inset,
            bottom: 0, right: isRightToLeft ? Self.inset : plusSide
        )
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        fadeHost.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(fadeHost)
        fadeHost.addSubview(scrollView)

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
        if needsRestingOffset {
            scrollView.layoutIfNeeded()
            if scrollView.contentSize.width > 0 {
                needsRestingOffset = false
                scrollView.contentOffset.x = isRightToLeft
                    ? scrollView.contentSize.width + scrollView.contentInset.right - scrollView.bounds.width
                    : -scrollView.contentInset.left
            }
        }
        updateFade()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateFade()
    }

    private var isRightToLeft: Bool {
        effectiveUserInterfaceLayoutDirection == .rightToLeft
    }

    /// Fades each end only while the row can scroll that way, growing in over the first `edgeFade`
    /// of travel. The leading fade runs `edgeFade` in from the edge; the trailing one runs
    /// `trailingFade` from the middle of the "+", and the rest of the row under the "+" is hidden to
    /// the same strength. At rest, with nothing to scroll back to, the leading edge draws solid.
    private func updateFade() {
        let width = fadeHost.bounds.width
        guard width > 0 else { return }
        let offset = scrollView.contentOffset.x
        let lowest = -scrollView.contentInset.left
        let highest = max(lowest, scrollView.contentSize.width + scrollView.contentInset.right - scrollView.bounds.width)
        let back = isRightToLeft ? highest - offset : offset - lowest
        let forward = isRightToLeft ? offset - lowest : highest - offset
        let leading = min(1, max(0, back / Self.edgeFade))
        let trailing = min(1, max(0, forward / Self.edgeFade))
        let clearFrom = width - Self.inset - Self.addSize / 2 + Self.trailingFade

        // Measured from the leading edge; flipped into the layer's left-to-right space below.
        let stops = [0, Self.edgeFade, clearFrom - Self.trailingFade, clearFrom, width].map { min(1, max(0, $0 / width)) }
        let alphas = [1 - leading, 1, 1, 1 - trailing, 1 - trailing]
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fade.frame = fadeHost.bounds
        if isRightToLeft {
            fade.startPoint = CGPoint(x: 1, y: 0.5)
            fade.endPoint = CGPoint(x: 0, y: 0.5)
        } else {
            fade.startPoint = CGPoint(x: 0, y: 0.5)
            fade.endPoint = CGPoint(x: 1, y: 0.5)
        }
        fade.colors = alphas.map { UIColor.black.withAlphaComponent($0).cgColor }
        fade.locations = stops.map { NSNumber(value: Double($0)) }
        CATransaction.commit()
    }

    func configure(entries: [ReactionStrip.Entry]) {
        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        for entry in entries {
            // Drawn as an image cropped to the glyph's ink, so the button centers the emoji itself
            // rather than the taller line box a title label would center.
            var configuration = UIButton.Configuration.plain()
            configuration.image = Self.glyphImage(entry.emoji)
            configuration.contentInsets = .zero
            let button = UIButton(configuration: configuration)
            button.backgroundColor = entry.highlighted ? UIColor.white.withAlphaComponent(0.18) : .clear
            button.layer.cornerRadius = Self.itemSize / 2
            button.clipsToBounds = true
            button.widthAnchor.constraint(equalToConstant: Self.itemSize).isActive = true
            button.heightAnchor.constraint(equalToConstant: Self.itemSize).isActive = true
            button.addAction(UIAction { [weak self] _ in self?.onSelect?(entry.emoji) }, for: .touchUpInside)
            button.accessibilityLabel = entry.emoji
            stack.addArrangedSubview(button)
        }
        needsRestingOffset = true
        setNeedsLayout()
    }

    private static var glyphImages: [String: UIImage] = [:]

    /// `emoji` at the strip's size, cropped to its drawn pixels.
    private static func glyphImage(_ emoji: String) -> UIImage {
        if let cached = glyphImages[emoji] { return cached }
        let text = NSAttributedString(string: emoji, attributes: [.font: emojiFont])
        let box = text.size()
        let line = UIGraphicsImageRenderer(size: CGSize(width: ceil(box.width), height: ceil(box.height))).image { _ in
            text.draw(at: .zero)
        }
        // Cropped by pixel rather than by `usesDeviceMetrics`, which stops Apple Color Emoji at the
        // baseline and would cut off everything below it.
        let image: UIImage
        if let cgImage = line.cgImage, let ink = inkBounds(of: cgImage), let cropped = cgImage.cropping(to: ink) {
            image = UIImage(cgImage: cropped, scale: line.scale, orientation: .up)
        } else {
            image = line
        }
        glyphImages[emoji] = image.withRenderingMode(.alwaysOriginal)
        return glyphImages[emoji]!
    }

    /// The smallest pixel rect holding every non-transparent pixel of `image`, or `nil` if it has none.
    private static func inkBounds(of image: CGImage) -> CGRect? {
        let width = image.width, height = image.height
        var alpha = [UInt8](repeating: 0, count: width * height)
        let drawn = alpha.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where alpha[y * width + x] > 0 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        // The context's rows run top to bottom in memory, the same order `cropping(to:)` counts.
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
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
