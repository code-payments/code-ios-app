//
//  LinkWebCardView.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit
import FlipcashCore

/// The web card: an outside page's image, host, title and description, drawn under the text inside
/// its bubble. Or, for a viewer outside the group, the "Show preview" chip that asks for it.
///
/// It draws nothing at all while the page is loading or had nothing to show, and then takes no
/// height, so the bubble stays the text bubble it would have been.
final class LinkWebCardView: UIView {

    /// What the card is drawing.
    enum Content: Equatable {
        case nothing
        case chip(host: String)
        case preview(LinkCard.Web.Resolved)
    }

    /// Called when the chip is tapped.
    var onShowPreview: (() -> Void)?
    /// Called when the drawn preview is tapped.
    var onTap: (() -> Void)?
    /// Fetches the preview image's bytes; nil draws the preview without its image.
    var loadImage: ((URL) async -> Data?)?

    private(set) var content: Content = .nothing

    /// Space between the text above and whatever the card draws. Inside the card, so a card that
    /// draws nothing adds nothing.
    static let topGap: CGFloat = 8
    /// The image's width over its height, as `og:image` is commonly cut.
    static let imageAspect: CGFloat = 1.91

    private let panel = UIView()
    private let stack = UIStackView()
    let imageView = UIImageView()
    let hostLabel = UILabel()
    let titleLabel = UILabel()
    let descriptionLabel = UILabel()
    let chip = UIButton(type: .system)

    /// Whether `point`, in this view's coordinates, is on the "Show preview" chip.
    func hasButton(at point: CGPoint) -> Bool {
        !chip.isHidden && chip.convert(chip.bounds, to: self).contains(point)
    }
    private var collapse: NSLayoutConstraint!
    private var imageTask: Task<Void, Never>?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setUp() {
        backgroundColor = .clear

        panel.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        panel.layer.cornerRadius = 10
        panel.layer.cornerCurve = .continuous
        panel.clipsToBounds = true
        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(panelTapped)))
        addSubview(panel)

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.isHidden = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(imageView)

        hostLabel.font = .default(size: 12, weight: .medium)
        hostLabel.textColor = UIColor.white.withAlphaComponent(0.6)
        hostLabel.numberOfLines = 1
        titleLabel.font = .default(size: 15, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 2
        descriptionLabel.font = .default(size: 13, weight: .regular)
        descriptionLabel.textColor = UIColor.white.withAlphaComponent(0.75)
        descriptionLabel.numberOfLines = 2

        stack.axis = .vertical
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        for label in [hostLabel, titleLabel, descriptionLabel] {
            stack.addArrangedSubview(label)
        }
        panel.addSubview(stack)

        chip.titleLabel?.font = .default(size: 13, weight: .bold)
        chip.setTitleColor(.white, for: .normal)
        chip.contentHorizontalAlignment = .leading
        chip.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        chip.layer.cornerRadius = 14
        chip.layer.cornerCurve = .continuous
        chip.contentEdgeInsets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        chip.titleLabel?.lineBreakMode = .byTruncatingMiddle
        // A long host truncates rather than widening the bubble around it.
        chip.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        chip.addTarget(self, action: #selector(chipTapped), for: .touchUpInside)
        chip.translatesAutoresizingMaskIntoConstraints = false
        addSubview(chip)

        // Only one of the image's two heights is ever live: a zero height competing with the aspect
        // would be settled by shrinking the width, and the card with it.
        imageHeight = imageView.heightAnchor.constraint(equalTo: imageView.widthAnchor, multiplier: 1 / Self.imageAspect)
        let stackBelowImage = stack.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 8)
        imageCollapsed = imageView.heightAnchor.constraint(equalToConstant: 0)

        collapse = heightAnchor.constraint(equalToConstant: 0)
        panelTop = panel.topAnchor.constraint(equalTo: topAnchor, constant: Self.topGap)
        chipTop = chip.topAnchor.constraint(equalTo: topAnchor, constant: Self.topGap)
        NSLayoutConstraint.activate([
            panelTop,
            panel.leadingAnchor.constraint(equalTo: leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: trailingAnchor),

            imageView.topAnchor.constraint(equalTo: panel.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: panel.trailingAnchor),

            stackBelowImage,
            stack.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -10),
            stack.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -10),

            chipTop,
            chip.leadingAnchor.constraint(equalTo: leadingAnchor),
            chip.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
        ])
        chipBottom = chip.bottomAnchor.constraint(equalTo: bottomAnchor)
        // The panel and the chip each close the card only while they draw, so the zero height of a
        // card that draws nothing never fights their gap above.
        panelBottom = panel.bottomAnchor.constraint(equalTo: bottomAnchor)
        imageCollapsed.isActive = true
        apply(.nothing)
    }

    private var imageHeight: NSLayoutConstraint!
    private var panelTop: NSLayoutConstraint!
    private var chipTop: NSLayoutConstraint!

    /// Whether the card stands on its own in place of its bubble: no gap above it, and the panel cut
    /// to `cornerRadii` rather than rounded inside a bubble.
    var isBare = false {
        didSet {
            guard isBare != oldValue else { return }
            panelTop.constant = isBare ? 0 : Self.topGap
            chipTop.constant = isBare ? 0 : Self.topGap
            setNeedsLayout()
        }
    }

    /// The bare panel's outline, for its place in its bubble run.
    var cornerRadii = BubbleBackgroundView.standaloneRadii {
        didSet { if cornerRadii != oldValue { setNeedsLayout() } }
    }

    private let panelMask = CAShapeLayer()

    override func layoutSubviews() {
        super.layoutSubviews()
        if isBare {
            panel.layer.cornerRadius = 0
            panelMask.path = BubbleBackgroundView.path(radii: cornerRadii, in: panel.bounds)
            panel.layer.mask = panelMask
        } else {
            panel.layer.cornerRadius = 10
            panel.layer.mask = nil
        }
    }
    private var imageCollapsed: NSLayoutConstraint!
    private var chipBottom: NSLayoutConstraint!
    private var panelBottom: NSLayoutConstraint!

    func prepareForReuse() {
        imageTask?.cancel()
        imageTask = nil
        apply(.nothing)
    }

    /// Draws `content`.
    /// - Returns: whether that changed what the card draws, and with it the card's height.
    @discardableResult
    func configure(with content: Content) -> Bool {
        guard content != self.content else { return false }
        apply(content)
        return true
    }

    private func apply(_ content: Content) {
        let previousImageURL = Self.imageURL(of: self.content)
        self.content = content

        switch content {
        case .nothing:
            panel.isHidden = true
            chip.isHidden = true
            chip.setTitle(nil, for: .normal)
            chipBottom.isActive = false
            panelBottom.isActive = false
            collapse.isActive = true

        case .chip(let host):
            panel.isHidden = true
            chip.isHidden = false
            chip.setTitle(Self.chipTitle(host: host), for: .normal)
            panelBottom.isActive = false
            collapse.isActive = false
            chipBottom.isActive = true

        case .preview(let page):
            chip.isHidden = true
            chipBottom.isActive = false
            panel.isHidden = false
            collapse.isActive = false
            panelBottom.isActive = true
            hostLabel.text = page.host
            titleLabel.text = page.title
            descriptionLabel.text = page.description
            descriptionLabel.isHidden = page.description == nil
        }

        let imageURL = Self.imageURL(of: content)
        if imageURL != previousImageURL {
            imageTask?.cancel()
            imageTask = nil
            if let imageURL, let loadImage {
                setImageSlot(.loading)
                load(imageURL, with: loadImage)
            } else {
                setImageSlot(.none)
            }
        }
    }

    /// Fetches the image and shows it only if the card still draws that same image.
    private func load(_ url: URL, with loadImage: @escaping (URL) async -> Data?) {
        imageTask = Task { [weak self] in
            let data = await loadImage(url)
            guard !Task.isCancelled, let self, Self.imageURL(of: content) == url else { return }
            if let data, let image = UIImage(data: data) {
                setImageSlot(.loaded(image))
            } else {
                setImageSlot(.none)
                onImageChange?()
            }
        }
    }

    /// Called when the image fails and the card drops the slot it held for it.
    var onImageChange: (() -> Void)?

    /// What the image slot shows. The slot is held at the image's shape while it loads, so a
    /// successful image doesn't move the text, and dropped only when the image fails.
    enum ImageSlot: Equatable {
        case none
        case loading
        case loaded(UIImage)
    }

    private(set) var imageSlot: ImageSlot = .none

    private func setImageSlot(_ slot: ImageSlot) {
        imageSlot = slot
        switch slot {
        case .none:
            imageView.image = nil
            imageView.isHidden = true
        case .loading:
            imageView.image = nil
            imageView.isHidden = false
            imageView.backgroundColor = Self.loadingTint
        case .loaded(let image):
            imageView.image = image
            imageView.isHidden = false
            imageView.backgroundColor = .clear
        }
        // Off before on, so the two heights are never live together.
        if slot == .none {
            imageHeight.isActive = false
            imageCollapsed.isActive = true
        } else {
            imageCollapsed.isActive = false
            imageHeight.isActive = true
        }
    }

    private static let loadingTint = UIColor.white.withAlphaComponent(0.15)

    private static func imageURL(of content: Content) -> URL? {
        if case .preview(let page) = content { page.imageURL } else { nil }
    }

    /// The chip's label. Pending UX review together with Android's string.
    static func chipTitle(host: String) -> String {
        "Show preview · \(host)"
    }

    @objc private func chipTapped() { onShowPreview?() }
    @objc private func panelTapped() { onTap?() }
}
#endif
