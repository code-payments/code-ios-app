//
//  ChatLinkMessageCell.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit
import FlipcashCore

/// A recycled cell for a text message that contains a link: a `LinkableBubbleView` (tappable text)
/// above a compact `LinkPreviewCardView`, stacked in a `ChatColumnCell` so the receipt sits below both.
/// A message whose text is only the URL hides the bubble and shows just the card. Metadata and the hero
/// image are fetched/cached off `LinkMetadataCache`; the card shows the domain immediately and fills in
/// the title, then the thumbnail, as each resolves, at a fixed height so nothing resizes mid-scroll.
public final class ChatLinkMessageCell: ChatColumnCell {

    public static let reuseIdentifier = "ChatLinkMessageCell"

    /// The card's fixed width (a hero image + caption, iOS-style); the card owns its own fixed height.
    static let cardWidth: CGFloat = 280

    private let bubble = LinkableBubbleView()
    private let card = LinkPreviewCardView()
    private let contentStack = UIStackView()
    private var loadTask: Task<Void, Never>?
    private var currentURL: URL?
    private var bubbleMaxWidthConstraint: NSLayoutConstraint!
    private var cardTap: UITapGestureRecognizer?

    /// The metadata cache; injectable for tests, defaults to the shared instance.
    var cache: LinkMetadataCache = .shared

    /// Called when the user taps the text link or the card.
    var onOpenURL: ((URL) -> Void)? {
        didSet { bubble.onOpenURL = onOpenURL }
    }

    /// The view + shape the context-menu lift clips to (the card when the bubble is hidden).
    var liftPreviewView: UIView { bubble.isHidden ? card : bubble }
    var liftPreviewMaskingPath: UIBezierPath? { bubble.isHidden ? nil : bubble.maskingPath }

    public override init(frame: CGRect) {
        super.init(frame: frame)

        contentStack.axis = .vertical
        contentStack.spacing = 4
        contentStack.addArrangedSubview(bubble)
        contentStack.addArrangedSubview(card)

        card.translatesAutoresizingMaskIntoConstraints = false
        let cardWidth = card.widthAnchor.constraint(equalToConstant: Self.cardWidth)
        cardWidth.priority = UILayoutPriority(999)

        installColumn(content: contentStack)
        bubbleMaxWidthConstraint = bubble.widthAnchor.constraint(lessThanOrEqualToConstant: Self.cardWidth)

        NSLayoutConstraint.activate([cardWidth, bubbleMaxWidthConstraint])

        let tap = UITapGestureRecognizer(target: self, action: #selector(cardTapped))
        card.addGestureRecognizer(tap)
        cardTap = tap
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public override func prepareForReuse() {
        super.prepareForReuse()
        loadTask?.cancel()
        loadTask = nil
        currentURL = nil
        bubble.prepareForReuse()
        card.prepareForReuse()
    }

    /// - Parameter maxWidth: the widest the text bubble may grow before its text wraps.
    public func configure(with message: ChatMessage, maxWidth: CGFloat) {
        bubbleMaxWidthConstraint.constant = maxWidth
        contentStack.alignment = message.sender == .me ? .trailing : .leading

        bubble.configure(with: message)
        bubble.isHidden = message.linkPreview?.bubbleText.isEmpty ?? false

        updateColumn(for: message)
        // A failed row's whole column is the retry target (ChatColumnCell); disable the card's own tap so a
        // tap on a failed link message retries the send rather than also opening the URL.
        cardTap?.isEnabled = !message.isFailed
        // Same reasoning for the bubble's own text-view link taps: a failed row must not let the text
        // view claim a tap that should retry the send.
        bubble.isUserInteractionEnabled = !message.isFailed

        guard let url = message.linkPreview?.url else {
            card.isHidden = true
            currentURL = nil
            return
        }
        card.isHidden = false
        // The card is a standalone rounded rect (no same-sender corner grouping) — it reads as a
        // distinct element under the bubble.
        card.apply(
            fill: BubbleBackgroundView.fill(isFromSelf: message.sender == .me),
            radii: BubbleBackgroundView.radii(isFromSelf: message.sender == .me, groupedAbove: false, groupedBelow: false)
        )
        // A cell reconfigures on every observable change to the row (read receipts, grouping); only
        // reload the card's content when the URL actually changed, so those reconfigures don't re-fetch
        // metadata that's already showing.
        guard url != currentURL else { return }
        // Show the domain immediately — the card is never blank while metadata is in flight.
        card.configure(url: url)
        loadCard(for: url)
    }

    private func loadCard(for url: URL) {
        currentURL = url
        loadTask?.cancel()

        // A cache hit applies synchronously — no Task, no dispatch delay — so a link that's already
        // warm (prefetched, or shown earlier in the transcript) never flashes the bare-domain state.
        if let cached = cache.cachedValue(for: url) {
            card.apply(metadata: cached.value)
            loadTask = Task { [weak self] in
                guard let self, let image = await cache.image(for: url, from: cached.value),
                      !Task.isCancelled, currentURL == url else { return }
                card.showHero(image)
            }
            return
        }

        loadTask = Task { [weak self] in
            guard let self, let metadata = await cache.metadata(for: url)?.value,
                  !Task.isCancelled, currentURL == url else { return }
            card.apply(metadata: metadata)
            guard let image = await cache.image(for: url, from: metadata),
                  !Task.isCancelled, currentURL == url else { return }
            card.showHero(image)
        }
    }

    @objc private func cardTapped() {
        guard let currentURL else { return }
        onOpenURL?(currentURL)
    }
}

extension ChatLinkMessageCell: BubbleCarrying {}
#endif
