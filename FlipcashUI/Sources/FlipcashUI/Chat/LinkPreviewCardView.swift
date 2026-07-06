//
//  LinkPreviewCardView.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit
import SwiftUI
import LinkPresentation

/// A rich link preview card mirroring the iOS / Messages layout — a hero image on top with a title +
/// domain caption below — restyled for the dark conversation surface using the shared
/// `BubbleBackgroundView` chrome (which masks its subview tree, so the hero clips to the rounded top
/// corners). The domain renders immediately from the bare URL (`configure(url:)`); the title fills in
/// once metadata resolves (`apply(metadata:)`) and the hero image once it's decoded (`showHero(_:)`),
/// at a fixed height so nothing resizes mid-scroll. Fetching and caching both are the hosting cell's job,
/// off `LinkMetadataCache`. Taps are owned by the hosting cell.
final class LinkPreviewCardView: UIView {

    private static let heroHeight: CGFloat = 150
    private static let cardHeight: CGFloat = 228

    private let background = BubbleBackgroundView()
    private let heroContainer = UIView()
    private let heroImage = UIImageView()
    private let placeholderIcon = UIImageView()
    private let titleLabel = UILabel()
    private let domainLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setUp() {
        background.translatesAutoresizingMaskIntoConstraints = false
        addSubview(background)

        heroContainer.backgroundColor = UIColor.white.withAlphaComponent(0.06)
        heroContainer.clipsToBounds = true
        heroContainer.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(heroContainer)

        placeholderIcon.image = UIImage(systemName: "link")
        placeholderIcon.tintColor = UIColor.white.withAlphaComponent(0.25)
        placeholderIcon.contentMode = .scaleAspectFit
        placeholderIcon.translatesAutoresizingMaskIntoConstraints = false
        heroContainer.addSubview(placeholderIcon)

        heroImage.contentMode = .scaleAspectFill
        heroImage.clipsToBounds = true
        heroImage.translatesAutoresizingMaskIntoConstraints = false
        heroContainer.addSubview(heroImage)

        titleLabel.font = .default(size: 15, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 2

        domainLabel.font = .default(size: 12, weight: .regular)
        domainLabel.textColor = UIColor.white.withAlphaComponent(0.5)
        domainLabel.numberOfLines = 1

        let caption = UIStackView(arrangedSubviews: [titleLabel, domainLabel])
        caption.axis = .vertical
        caption.spacing = 2
        caption.alignment = .leading
        caption.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(caption)

        let heightConstraint = heightAnchor.constraint(equalToConstant: Self.cardHeight)
        heightConstraint.priority = UILayoutPriority(999)

        NSLayoutConstraint.activate([
            background.topAnchor.constraint(equalTo: topAnchor),
            background.bottomAnchor.constraint(equalTo: bottomAnchor),
            background.leadingAnchor.constraint(equalTo: leadingAnchor),
            background.trailingAnchor.constraint(equalTo: trailingAnchor),
            heightConstraint,

            heroContainer.topAnchor.constraint(equalTo: background.topAnchor),
            heroContainer.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            heroContainer.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            heroContainer.heightAnchor.constraint(equalToConstant: Self.heroHeight),

            placeholderIcon.centerXAnchor.constraint(equalTo: heroContainer.centerXAnchor),
            placeholderIcon.centerYAnchor.constraint(equalTo: heroContainer.centerYAnchor),
            placeholderIcon.widthAnchor.constraint(equalToConstant: 28),
            placeholderIcon.heightAnchor.constraint(equalToConstant: 28),

            heroImage.topAnchor.constraint(equalTo: heroContainer.topAnchor),
            heroImage.bottomAnchor.constraint(equalTo: heroContainer.bottomAnchor),
            heroImage.leadingAnchor.constraint(equalTo: heroContainer.leadingAnchor),
            heroImage.trailingAnchor.constraint(equalTo: heroContainer.trailingAnchor),

            caption.topAnchor.constraint(equalTo: heroContainer.bottomAnchor, constant: 10),
            caption.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 12),
            caption.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -12),
            caption.bottomAnchor.constraint(lessThanOrEqualTo: background.bottomAnchor, constant: -12),
        ])
    }

    /// The card's chrome, matching the bubbles. Always a standalone (ungrouped) rounded rect.
    func apply(fill: UIColor, radii: RectangleCornerRadii) {
        background.apply(fill: fill, radii: radii)
    }

    func prepareForReuse() {
        titleLabel.text = nil
        domainLabel.text = nil
        heroImage.image = nil
        heroImage.alpha = 1
        placeholderIcon.isHidden = false
    }

    /// Shows the domain immediately, before metadata resolves — the card is never blank.
    func configure(url: URL) {
        let host = Self.displayHost(for: url)
        domainLabel.text = host
        titleLabel.text = host
        heroImage.image = nil
        placeholderIcon.isHidden = false
    }

    /// Fills in the real title once metadata resolves. The hero image is a separate step
    /// (`showHero(_:)`) — the cell fetches it independently, off `LinkMetadataCache`.
    func apply(metadata: LPLinkMetadata) {
        let host = metadata.url.map(Self.displayHost(for:)) ?? domainLabel.text
        titleLabel.text = metadata.title ?? host
    }

    /// Fades in the decoded hero image once the cell's fetch resolves.
    func showHero(_ image: UIImage) {
        heroImage.image = image
        placeholderIcon.isHidden = true
        heroImage.alpha = 0
        UIView.animate(withDuration: 0.2) { self.heroImage.alpha = 1 }
    }

    private static func displayHost(for url: URL) -> String {
        let host = url.host ?? url.absoluteString
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
#endif
