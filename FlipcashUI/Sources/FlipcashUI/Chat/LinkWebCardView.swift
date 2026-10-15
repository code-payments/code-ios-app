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
/// its bubble, from the preview its sender attached.
///
/// It draws nothing at all for a message without a preview, and then takes no height, so the bubble
/// stays the text bubble it would have been.
final class LinkWebCardView: UIView {

    /// What the card is drawing.
    enum Content: Equatable {
        case nothing
        case preview(Page)
    }

    /// The page as the card draws it.
    struct Page: Equatable {
        /// The link's own host, without its "www.".
        let host: String
        let title: String
        let description: String?
        /// The page's image, a chat blob like any photo.
        let image: MediaAttachment?

        init(host: String, title: String, description: String?, image: MediaAttachment?) {
            self.host = host
            self.title = title
            self.description = description
            self.image = image
        }
    }

    /// Called when the drawn preview is tapped.
    var onTap: (() -> Void)?
    /// Loads the preview image; nil draws the preview without its image.
    var loadImage: ((MediaAttachment) async -> UIImage?)?
    /// The preview image if already in memory; a hit draws on this frame, with no loading slot.
    var cachedImage: ((MediaAttachment) -> UIImage?)?

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
        for view in [hostLabel, titleLabel, descriptionLabel] {
            stack.addArrangedSubview(view)
        }
        stack.setCustomSpacing(6, after: hostLabel)
        panel.addSubview(stack)

        // Only one of the image's two heights is ever live: a zero height competing with the aspect
        // would be settled by shrinking the width, and the card with it.
        imageHeight = imageView.heightAnchor.constraint(equalTo: imageView.widthAnchor, multiplier: 1 / Self.imageAspect)
        let stackBelowImage = stack.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 8)
        imageCollapsed = imageView.heightAnchor.constraint(equalToConstant: 0)

        collapse = heightAnchor.constraint(equalToConstant: 0)
        panelTop = panel.topAnchor.constraint(equalTo: topAnchor, constant: Self.topGap)
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
        ])
        // The panel closes the card only while it draws, so the zero height of a card that draws
        // nothing never fights its gap above.
        panelBottom = panel.bottomAnchor.constraint(equalTo: bottomAnchor)
        imageCollapsed.isActive = true
        apply(.nothing)
    }

    private var imageHeight: NSLayoutConstraint!
    private var panelTop: NSLayoutConstraint!

    /// Whether the card stands on its own in place of its bubble: no gap above it, and the panel cut
    /// to `cornerRadii` rather than rounded inside a bubble.
    var isBare = false {
        didSet {
            guard isBare != oldValue else { return }
            panelTop.constant = isBare ? 0 : Self.topGap
            setNeedsLayout()
        }
    }

    /// The bare panel's outline, for its place in its bubble run.
    var cornerRadii = BubbleBackgroundView.standaloneRadii {
        didSet { if cornerRadii != oldValue { setNeedsLayout() } }
    }

    private let panelMask = CAShapeLayer()

    /// The bare card's edge, the bare group card's outline. An opaque page image can match the chat
    /// background, so without it the card's top has no edge.
    let outline: CAShapeLayer = {
        let layer = CAShapeLayer()
        layer.fillColor = nil
        layer.strokeColor = UIColor.white.withAlphaComponent(0.1).cgColor
        layer.lineWidth = 1
        return layer
    }()

    override func layoutSubviews() {
        super.layoutSubviews()
        if isBare {
            panel.layer.cornerRadius = 0
            panelMask.path = BubbleBackgroundView.path(radii: cornerRadii, in: panel.bounds)
            panel.layer.mask = panelMask
            // Inset by half the line so it sits inside the mask, and re-added so it draws over the image.
            outline.path = BubbleBackgroundView.path(radii: cornerRadii, in: panel.bounds.insetBy(dx: 0.5, dy: 0.5))
            panel.layer.addSublayer(outline)
        } else {
            panel.layer.cornerRadius = 10
            panel.layer.mask = nil
            outline.removeFromSuperlayer()
        }
    }
    private var imageCollapsed: NSLayoutConstraint!
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
        let previousImage = Self.image(of: self.content)
        self.content = content

        switch content {
        case .nothing:
            panel.isHidden = true
            panelBottom.isActive = false
            collapse.isActive = true

        case .preview(let page):
            panel.isHidden = false
            collapse.isActive = false
            panelBottom.isActive = true
            hostLabel.text = page.host
            titleLabel.text = page.title
            descriptionLabel.text = page.description
            descriptionLabel.isHidden = page.description == nil
        }

        let image = Self.image(of: content)
        guard image != previousImage else { return }
        imageTask?.cancel()
        imageTask = nil
        if let image, let cached = cachedImage?(image) {
            setImageSlot(.loaded(cached))
        } else if let image, let loadImage {
            setImageSlot(.loading(BlurHashCache.shared.image(for: image.blurhash)))
            load(image, with: loadImage)
        } else {
            setImageSlot(.none)
        }
    }

    /// Loads the image and shows it only if the card still draws that same image.
    private func load(_ image: MediaAttachment, with loadImage: @escaping (MediaAttachment) async -> UIImage?) {
        imageTask = Task { [weak self] in
            let loaded = await loadImage(image)
            guard !Task.isCancelled, let self, Self.image(of: content) == image else { return }
            if let loaded {
                setImageSlot(.loaded(loaded))
            } else {
                setImageSlot(.none)
                onImageChange?()
            }
        }
    }

    /// Called when the image fails and the card drops the slot it held for it.
    var onImageChange: (() -> Void)?

    /// What the image slot shows. The slot is held at the image's shape while it loads, under the
    /// image's BlurHash when it has one, so a successful image doesn't move the text, and dropped
    /// only when the image fails.
    enum ImageSlot: Equatable {
        case none
        case loading(UIImage?)
        case loaded(UIImage)
    }

    private(set) var imageSlot: ImageSlot = .none

    private func setImageSlot(_ slot: ImageSlot) {
        imageSlot = slot
        switch slot {
        case .none:
            imageView.image = nil
            imageView.isHidden = true
        case .loading(let blurhash):
            imageView.image = blurhash
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

    private static func image(of content: Content) -> MediaAttachment? {
        switch content {
        case .preview(let page): page.image
        case .nothing: nil
        }
    }

    @objc private func panelTapped() { onTap?() }
}

/// Where a transcript's web cards get their images: the chat photo pipeline, so a sealed preview
/// image decrypts and caches exactly as a sealed photo does.
@MainActor
struct WebCardImages {
    /// Loads the image, or nil when it fails to load or decrypt.
    let load: (MediaAttachment) async -> UIImage?
    /// The image if already held in memory.
    let cached: (MediaAttachment) -> UIImage?

    /// Images resolved through `resolver`.
    init(resolver: ChatMediaURLResolver) {
        load = { [weak resolver] attachment in
            guard let location = await resolver?.location(for: attachment) else { return nil }
            return await ChatMediaImageSource.image(blobID: attachment.blobID, location: location)
        }
        cached = { attachment in
            attachment.blobID.flatMap(ChatMediaImageSource.cachedImage(blobID:))
        }
    }

    init(load: @escaping (MediaAttachment) async -> UIImage?, cached: @escaping (MediaAttachment) -> UIImage?) {
        self.load = load
        self.cached = cached
    }
}
#endif
